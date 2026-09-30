class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  # Gatilho POSITIVO: o handoff não é só pra "quando você não consegue" — é o passo normal
  # de passar um lead qualificado pra uma pessoa fechar. A descrição antiga ("when unable to
  # assist further") fazia a IA quase nunca chamar o tool (uma IA que está atendendo bem nunca
  # se considera "unable to assist"), então nenhum lead chegava ao humano.
  description 'Passa a conversa para um ATENDENTE HUMANO do time assumir. Use quando já ' \
              'qualificou o cliente e é hora de uma pessoa continuar: ele quer visitar, ' \
              'agendar ou fechar; pediu falar com um humano; o assunto exige uma pessoa ' \
              '(jurídico, uma ação que você não executa); ou você não conseguiu resolver. ' \
              'A IA continua respondendo normalmente até um humano assumir.'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false
  param :team_id, type: 'string', desc: 'ID of the team to route the conversation to (optional)', required: false

  # Segmentos de campanha. O dado já existe na conversa (carimbado na criação do lead
  # Meta) — aqui só é LIDO, nada de heurística nova. Precedência: campanha > label.
  SEGMENTOS = {
    'economico' => { campanhas: ['[FORMS] - PACAEMBU'], labels: %w[pacaembu] },
    'remarketing' => { campanhas: ['[FORMS] - RMKT VENDAS - 2026'], labels: %w[rmkt-vendas-2026] },
    'empreendimentos' => { campanhas: ['[FORMS] - ETNA'], labels: %w[lead-spl-2026 etna] }
  }.freeze

  # Só o econômico exige nível antes de passar: é onde o handoff dispara cedo demais
  # (medido: 248 handoffs por "reagiu bem", metade sem carimbo). No remarketing o
  # handoff rápido é o comportamento CERTO — nada a segurar.
  SEGMENTO_COM_PORTAO = 'economico'.freeze
  # Válvula de escape: portão que recusa pra sempre prende o cliente se o modelo não
  # conseguir satisfazer. Depois deste número de recusas, passa e registra.
  MAX_RECUSAS = 2
  CHAVE_RECUSAS = 'handoff_recusas_sem_prioridade'.freeze
  HANDOFF_JA_FEITO = 'A conversa já está com a equipe humana; nada foi refeito e não é preciso chamar esta ' \
                     'ferramenta de novo. Siga conforme suas instruções até uma pessoa assumir.'.freeze

  # RubyLLM::Tool delega description da instância para a classe — override de instância,
  # DINÂMICO por conta (tools são instanciadas a cada run: assistant.agent → agent_tools →
  # .new(self), então chega sempre fresco no LLM):
  #  - modo "a IA não escolhe" (account.custom_attributes['handoff_team_id'] setado): não enumera
  #    times, então na prática o modelo quase nunca passa `team_id` e o destino vira o time padrão
  #    do PRÓPRIO agente (HumanHandoffService#resolve_team).
  #  - modo "IA decide" (sem config, DEFAULT): enumera os times pra IA rotear pelo assunto
  #    (param team_id) — comportamento pra clientes que querem a IA definindo o setor.
  #
  # ⚠️ O VALOR da chave é IGNORADO — só a presença dela importa. Este comentário dizia que "todo
  # handoff cai no time configurado", e isso NUNCA foi verdade: o `resolve_team` não lê
  # `handoff_team_id` em lugar nenhum. Na Tozi a chave aponta para recepção (60) desde que foi
  # posta como paliativo até o rodízio ficar pronto; medido em 60 dias, dos 641 handoffs apenas 81
  # foram para a recepção — e os 81 eram da Clara, cujo time padrão já é o 60. Nenhum outro agente
  # jamais mandou para lá. Quem quiser destino único de verdade tem que implementar, não configurar.
  #
  # A enumeração respeita a allowlist da conta (`Account#handoff_teams`): time fora dela nem
  # é oferecido ao modelo. Isso é ADVISORY — quem recusa de fato é o HumanHandoffService,
  # porque o modelo pode passar um id que ninguém enumerou.
  def description
    base = self.class.description
    return base.to_s if fixed_handoff_team?

    teams = @assistant.account.handoff_teams.order(:id).map { |t| "#{t.id}: #{t.name}" }.join('; ')
    teams.present? ? "#{base} Times disponíveis (id: nome) — #{teams}. Roteie pelo assunto passando o team_id." : base.to_s
  end

  def fixed_handoff_team?
    @assistant.account.custom_attributes&.dig('handoff_team_id').present?
  end

  # Mesmo critério da description: no modo "a IA não escolhe", o destino é o time padrão do agente
  # e `team_id` seria um parâmetro morto no esquema. O RubyLLM monta o esquema a partir daqui.
  def parameters
    fixed_handoff_team? ? super.except(:team_id) : super
  end

  def perform(tool_context, reason: nil, team_id: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    # Idempotência: com a conversa JÁ aguardando humano, ou com um humano já dono, não refaz o
    # handoff (senão gera 2ª nota/dossiê, reseta o marcador e pode redistribuir para outra pessoa).
    motivo = handoff_ja_feito(conversation)
    if motivo
      registrar_handoff_ja_pendente(conversation, motivo)
      return HANDOFF_JA_FEITO
    end

    recusa = portao_do_segmento(conversation)
    return recusa if recusa

    registrar_e_disparar(conversation, reason, team_id)

    'Time humano acionado: dossiê registrado e conversa marcada como aguardando atendente. ' \
      'Na SUA resposta, avise o cliente que uma pessoa do time vai assumir e CONTINUE atendendo ' \
      'normalmente até o atendente assumir de fato.'
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  # A IA segue atendendo depois do handoff (Modelo A) e não enxerga a chamada anterior, então
  # re-chama a ferramenta: 39% das chamadas na conta medida. `assignee_id` cobre a corrida em que
  # alguém puxa a conversa no meio do turno — o service só se protegia do marcador.
  def handoff_ja_feito(conversation)
    return 'aguardando_humano' if conversation.custom_attributes&.dig('aguardando_humano_desde').present?

    'humano_atribuido' if conversation.assignee_id.present?
  end

  # Registro barato só para medir a re-chamada; nunca derruba a resposta à IA.
  def registrar_handoff_ja_pendente(conversation, motivo)
    Captain::AssistantLog.create!(captain_assistant: @assistant, conversation: conversation,
                                  event_type: 'handoff_ja_pendente', payload: { 'motivo' => motivo })
  rescue StandardError => e
    Rails.logger.warn("[HandoffTool] handoff_ja_pendente: #{e.message}")
  end

  def registrar_e_disparar(conversation, reason, team_id)
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     segmento: segmento(conversation),
                     prioridade: conversation.custom_attributes&.dig('prioridade'),
                     reason: reason || 'Agent requested handoff'
                   })
    trigger_handoff(conversation, montar_dossie(conversation, reason), team_id)
  end

  def segmento(conversation)
    attrs = conversation.custom_attributes || {}
    campanha = attrs['meta_campanha'].to_s
    labels = conversation.label_list.map(&:to_s)
    SEGMENTOS.each do |nome, regra|
      return nome if regra[:campanhas].include?(campanha)
      return nome if regra[:labels].intersect?(labels)
    end
    nil
  end

  # nil = pode passar. String = recusa, já no formato de instrução ao agente.
  # Só o econômico tem portão; segmento desconhecido segue o comportamento de sempre.
  def portao_do_segmento(conversation)
    return nil unless segmento(conversation) == SEGMENTO_COM_PORTAO
    return nil if conversation.custom_attributes&.dig('prioridade').present?

    recusas = conversation.custom_attributes.to_h[CHAVE_RECUSAS].to_i
    if recusas >= MAX_RECUSAS
      log_tool_usage('handoff_sem_prioridade_liberado',
                     conversation_id: conversation.id, recusas: recusas)
      return nil
    end

    registrar_recusa(conversation, recusas + 1)
    'Este lead é de campanha do produto econômico, onde o corretor precisa do NÍVEL de qualificação pra priorizar. ' \
      'Antes de passar, chame salvar_info_lead com `prioridade` (quente, morno ou frio) e, quando o cliente tiver ' \
      'falado disso, com `renda_comprovavel`, `restricao_nome` e `caminho_alternativo`. ' \
      'Se ele não fecha por renda ou por nome, isso NÃO o descarta: registre o caminho que ele apontou e passe como morno. ' \
      'Depois chame o handoff de novo.'
  end

  def registrar_recusa(conversation, total)
    conversation.update!(custom_attributes: conversation.custom_attributes.to_h.merge(CHAVE_RECUSAS => total))
  rescue StandardError => e
    Rails.logger.warn("[HandoffTool] recusa: #{e.message}")
  end

  # O corretor lê a nota privada e precisa saber, sem abrir a conversa, o nível e o que
  # o sustenta. O texto do agente entra abaixo do cabeçalho, não é substituído.
  def montar_dossie(conversation, reason)
    attrs = conversation.custom_attributes || {}
    linhas = []
    linhas << "Prioridade: #{attrs['prioridade'].upcase}#{sustentacao(attrs)}" if attrs['prioridade'].present?
    linhas << "Caminho apontado pelo cliente: #{attrs['caminho_alternativo']}" if attrs['caminho_alternativo'].present?
    linhas << "Status do lead: #{attrs['tozi_status_lead']}" if attrs['tozi_status_lead'].present?
    seg = segmento(conversation)
    linhas << "Segmento: #{seg}" if seg
    return reason if linhas.empty?

    [linhas.join("\n"), reason.to_s.strip.presence].compact.join("\n\n")
  end

  def sustentacao(attrs)
    partes = []
    partes << "renda comprovável: #{attrs['renda_comprovavel']}" if attrs['renda_comprovavel'].present?
    partes << "restrição no nome: #{attrs['restricao_nome']}" if attrs['restricao_nome'].present?
    partes.any? ? " (#{partes.join(' · ')})" : ''
  end

  # Modelo A (decisão Paulo): a IA NÃO solta a conversa no handoff — segue dona e
  # respondendo até um humano PUXAR a atribuição. A lógica (abrir a conversa, rotear pro
  # time, marcar `aguardando_humano_desde`, distribuir) vive no HumanHandoffService, fonte
  # única reusada também pelo FollowupJob quando as cutucadas in-window esgotam.
  def trigger_handoff(conversation, reason, team_id = nil)
    Captain::Conversation::HumanHandoffService.new(
      conversation: conversation, assistant: @assistant, reason: reason, team_id: team_id
    ).perform
  end

  # TODO: Future enhancement
  # This tool could be enhanced to:
  # 1. Set conversation priority based on handoff reason
  # 2. Add metadata for intelligent agent assignment
  # 3. Support escalation levels (L1 -> L2 -> L3)
  #
  # Example future signature:
  # param :priority, type: 'string', desc: 'Priority level (low/medium/high/urgent)', required: false
  # param :escalation_level, type: 'string', desc: 'Support level (L1/L2/L3)', required: false
end
