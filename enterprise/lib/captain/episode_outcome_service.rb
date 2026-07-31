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

  # Tools que registram a intenção de passar pro humano.
  HANDOFF_TOOLS = %w[handoff transferir_para_agente].freeze

  # Quem conta como "a IA falando" (AgentBot cobre o espelho do assistant).
  IA_SENDERS = %w[Captain::Assistant AgentBot].freeze

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

  # A INTENÇÃO da IA de passar o bastão. Só é reconstituível onde o F2 gravou a tool
  # — e isso é uma limitação de observabilidade do produto, não uma escolha:
  #
  #   · `aguardando_humano_desde` é TRANSITÓRIO. É um "está aguardando", limpo quando
  #     o humano assume. Medido em produção (conta 6): 2 conversas em 20.170 o têm.
  #     Servia de gate de estado, jamais de registro histórico — a v1 deste serviço
  #     errou nisso e ficou cega pro desfecho mais comum dos dados.
  #   · AssistantLog 'handoff' NUNCA é escrito. O event_type existe em EVENT_TYPES,
  #     mas o HandoffTool só chama log_tool_usage, que escreve no Rails.logger e não
  #     cria registro. Constante morta (ver AVISO no doc do F3).
  #
  # Por isso o degrau DURÁVEL da escada é o `assumido`, não o `handoff`.
  def handoff
    call = tool_calls.find { |c| HANDOFF_TOOLS.include?(c.tool_name) && c.status == 'ok' }
    return if call.nil?

    { degrau: 'handoff', causado_por: 'ia', origem: 'tool',
      ator_id: call.captain_assistant_id, ocorreu_em: call.created_at,
      detalhe: { 'tool_call_id' => call.id, 'tool' => call.tool_name } }
  end

  # Um humano ASSUMIU o atendimento — o desfecho mais comum nos dados reais e o mais
  # durável de detectar. A mensagem é a evidência forte: o humano FALOU, não só foi
  # atribuído (atribuição sem resposta não é atendimento).
  def assumido
    msg = mensagens.find { |m| m.outgoing? && m.sender_type == 'User' }
    return if msg.nil?

    { degrau: 'assumido', causado_por: 'humano', origem: 'mensagem', ator_id: msg.sender_id,
      ocorreu_em: msg.created_at,
      detalhe: { 'message_id' => msg.id, 'ia_atendia_antes' => ia_atendia_antes?(msg) } }
  end

  # A IA estava conduzindo antes de o humano entrar? Sem isso, atendimento que SEMPRE
  # foi humano entraria como conversão da IA.
  #
  # O log 'human_takeover' responde sozinho: o log_captain_mirror_transition só o emite
  # quando o espelho captain ESTAVA na conversa e foi solto — ou seja, a existência do
  # registro já prova que a IA atendia. A varredura das mensagens é o complemento pra
  # conversa que nunca teve espelho.
  def ia_atendia_antes?(msg)
    return true if takeover_log.present?

    mensagens.any? { |m| m.outgoing? && IA_SENDERS.include?(m.sender_type) && m.created_at < msg.created_at }
  end

  def takeover_log
    return @takeover_log if defined?(@takeover_log)

    @takeover_log = Captain::AssistantLog
                    .where(conversation_id: conversation.id, event_type: 'human_takeover')
                    .where(created_at: episode.started_at..(fim + TOOL_WINDOW))
                    .order(:created_at).first
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
