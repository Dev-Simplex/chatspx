# Registra o DESFECHO de um episódio (Eval 2.0 F3) a partir de sinais que já existem
# no produto. Custo zero: nenhuma chamada de LLM, nenhuma tool nova.
#
# O juiz fica FORA do caminho do dado de conversão por construção — o que ele produz
# é veredito (opinião, reprocessável), o que este serviço produz é fato observado.
#
# Idempotente por (episode, degrau): roda no fluxo (EpisodeEvalJob) e em backfill
# (spx:eval:outcomes) sem duplicar nem re-datar.
#
# ⚠️ Todo degrau exige um sinal COM TIMESTAMP dentro da janela do episódio. Ler estado
# atual (custom_attributes, label, estágio do card) sem data carimbaria o mesmo desfecho
# em TODOS os episódios seguintes do contato — a conversa é perpétua e o estado persiste.
class Captain::EpisodeOutcomeService
  # Mesma folga do gate: a tool dispara logo depois da mensagem que a motivou.
  TOOL_WINDOW = 3.minutes

  # status do salvar_info_lead → degrau
  STATUS_DEGRAU = {
    'qualificado' => 'qualificado',
    'convertido' => 'qualificado',
    'esfriado' => 'esfriou',
    'perdido' => 'esfriou',
    'nao_qualificado' => 'descartado'
  }.freeze

  # automation_type do estágio → degrau. Caminho de quando NINGUÉM chamou a tool e o
  # card foi movido no Kanban (o FunnelItem tem moved_at + moved_by_id: timestamp e
  # autor, os dois de que precisamos).
  STAGE_DEGRAU = { 'qualificado' => 'qualificado', 'frio' => 'esfriou' }.freeze

  # Tools que levam ao marcador de handoff — todas passam pelo HumanHandoffService.
  HANDOFF_TOOLS = %w[handoff transferir_para_agente].freeze

  pattr_initialize [:episode!]

  def perform
    return [] unless Captain::ConversationEval.enabled_for?(episode.account)

    detectar.filter_map { |attrs| upsert(attrs) }
  end

  private

  # Precedência: tool antes de funil. Quando os dois apontam o mesmo degrau (a tool
  # move o card), fica o da tool — tem timestamp exato e prova de autoria da IA.
  def detectar
    encontrados = {}
    [respondeu, *por_tool_call, *por_funnel, handoff, assumido].compact.each do |outcome|
      encontrados[outcome[:degrau]] ||= outcome
    end
    encontrados.values
  end

  def conversation
    @conversation ||= episode.conversation
  end

  def fim
    @fim ||= episode.ended_at || Time.current
  end

  def mensagens
    @mensagens ||= conversation.messages
                               .where(id: episode.first_message_id..episode.last_message_id)
                               .where(private: false)
                               .reorder(:created_at)
                               .to_a
  end

  def tool_calls
    @tool_calls ||= Captain::ToolCall.for_conversation(conversation.id)
                                     .in_window(episode.started_at, fim + TOOL_WINDOW)
                                     .order(:created_at)
                                     .to_a
  end

  def na_janela?(instante)
    instante.present? && instante.between?(episode.started_at, fim + TOOL_WINDOW)
  end

  # ── degraus ────────────────────────────────────────────────────────────────

  # O lead deu sinal de vida. Denominador de "o opener funcionou".
  def respondeu
    primeira = mensagens.find(&:incoming?)
    return if primeira.nil?

    { degrau: 'respondeu', causado_por: 'contato', origem: 'mensagem',
      ocorreu_em: primeira.created_at, detalhe: { 'message_id' => primeira.id } }
  end

  # Caminho da IA: ela chamou salvar_info_lead com um status que move a escada.
  def por_tool_call
    tool_calls.filter_map do |call|
      next unless call.tool_name == 'salvar_info_lead' && call.status == 'ok'

      degrau = STATUS_DEGRAU[call.args['status'].to_s]
      next if degrau.nil?

      { degrau: degrau, causado_por: 'ia', origem: 'tool', ator_id: call.captain_assistant_id,
        ocorreu_em: call.created_at,
        detalhe: { 'tool_call_id' => call.id, 'status_lead' => call.args['status'] } }
    end
  end

  # Caminho humano/sistema: o card mudou de estágio dentro da janela. Genérico de
  # propósito — casa por automation_type, então vale pra qualquer conta cujo funil
  # use esse vocabulário, sem acoplar o eval ao funil de um cliente.
  def por_funnel
    item = conversation.funnel_items
                       .joins(:funnel_stage)
                       .where(funnel_stages: { automation_type: STAGE_DEGRAU.keys })
                       .order(moved_at: :desc)
                       .first
    return [] if item.nil? || !na_janela?(item.moved_at)

    degrau = STAGE_DEGRAU[item.funnel_stage.automation_type]
    return [] if degrau.nil?

    [{ degrau: degrau, causado_por: item.moved_by_id.present? ? 'humano' : 'sistema',
       origem: 'funnel', ator_id: item.moved_by_id, ocorreu_em: item.moved_at,
       detalhe: { 'stage' => item.funnel_stage.automation_type, 'funnel_item_id' => item.id } }]
  end

  # `aguardando_humano_desde` é ele próprio um timestamp ISO8601 — o gate de janela
  # sai de graça. Escrito SÓ pelo HumanHandoffService, chamado do HandoffTool, do
  # TransferirParaAgenteTool, do fallback do ResponseBuilderJob e da escalada do
  # FollowupJob: nenhum caminho humano escreve esse marcador, então a autoria aqui é
  # 'ia' (pediu via tool) ou 'sistema' (fallback/escalada) — nunca 'humano'.
  def handoff
    return if handoff_at.nil?

    call = tool_calls.find { |c| HANDOFF_TOOLS.include?(c.tool_name) && c.status == 'ok' }
    { degrau: 'handoff', causado_por: call ? 'ia' : 'sistema',
      origem: call ? 'tool' : 'atributo', ator_id: call&.captain_assistant_id,
      ocorreu_em: handoff_at,
      detalhe: { 'tool_call_id' => call&.id, 'tool' => call&.tool_name }.compact }
  end

  def handoff_at
    return @handoff_at if defined?(@handoff_at)

    bruto = conversation.custom_attributes&.dig('aguardando_humano_desde')
    instante = bruto.present? ? Time.zone.parse(bruto.to_s) : nil
    @handoff_at = na_janela?(instante) ? instante : nil
  rescue ArgumentError
    @handoff_at = nil
  end

  # Um humano de fato respondeu DEPOIS do handoff. Exige o handoff nesta janela: sem
  # ele não é "assumido", é só um humano trabalhando a conversa — e se o handoff foi
  # num episódio anterior, o crédito é daquele episódio, não deste.
  def assumido
    return if handoff_at.nil?

    msg = mensagens.find do |m|
      m.outgoing? && m.sender_type == 'User' && m.created_at >= handoff_at
    end
    return if msg.nil?

    { degrau: 'assumido', causado_por: 'humano', origem: 'mensagem', ator_id: msg.sender_id,
      ocorreu_em: msg.created_at, detalhe: { 'message_id' => msg.id } }
  end

  # ── persistência ───────────────────────────────────────────────────────────

  def upsert(attrs)
    record = Captain::EpisodeOutcome.find_or_initialize_by(episode_id: episode.id, degrau: attrs[:degrau])
    record.assign_attributes(
      account_id: episode.account_id,
      conversation_id: conversation.id,
      **attrs,
      **segmentacao
    )
    record.save!
    record
  rescue StandardError => e
    Rails.logger.warn("[eval-outcome] episódio #{episode.id} degrau #{attrs[:degrau]}: #{e.class} #{e.message}")
    nil
  end

  # Congela a origem do lead no momento do registro (ver comentário da migration).
  def segmentacao
    attrs = conversation.custom_attributes || {}
    { campanha: attrs['meta_campanha'], anuncio: attrs['meta_anuncio'],
      publico: attrs['meta_publico'], empreendimento: attrs['empreendimento'],
      lead_tipo: attrs['meta_tipo'] }
  end
end
