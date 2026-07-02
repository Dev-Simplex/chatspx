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

  # RubyLLM::Tool delega description da instância para a classe — override de instância
  # enumera os times da conta (tools são instanciadas a cada run: assistant.agent →
  # agent_tools → .new(self)), então a lista chega sempre fresca no LLM.
  def description
    teams = @assistant.account.teams.order(:id).map { |t| "#{t.id}: #{t.name}" }.join('; ')
    base = self.class.description
    teams.present? ? "#{base}. Available teams (id: name) — #{teams}" : base.to_s
  end

  def perform(tool_context, reason: nil, team_id: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    # Idempotência: se a conversa JÁ está aguardando humano, não refaz o handoff (senão gera
    # uma 2ª nota privada/dossiê duplicado e reseta o marcador a cada mensagem do cliente na espera).
    if conversation.custom_attributes&.dig('aguardando_humano_desde').present?
      return 'Esta conversa JÁ está aguardando atendimento humano — o handoff já foi feito. ' \
             'NÃO chame o handoff de novo nem registre outro dossiê. Responda dúvidas NOVAS ' \
             'normalmente; se for só cobrança de pressa/ansiedade sem pergunta nova, responda [IGNORAR].'
    end

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    trigger_handoff(conversation, reason, team_id)

    'Time humano acionado: dossiê registrado e conversa marcada como aguardando atendente. ' \
      'Na SUA resposta, avise o cliente que uma pessoa do time vai assumir e CONTINUE atendendo ' \
      'normalmente até o atendente assumir de fato.'
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  # Modelo A (decisão Paulo): a IA NÃO solta a conversa no handoff — ela SEGUE dona e
  # respondendo até um humano PUXAR a atribuição ("Assumir conversa"). Isso evita
  # abandonar o lead (ex.: handoff num sábado à noite, sem ninguém pra assumir até
  # segunda — a IA segura o cliente nesse meio-tempo).
  #
  # A espera é sinalizada pelo custom attribute `aguardando_humano_desde`. A conversa fica
  # "atribuída à IA + marcador" → aparece no filtro "Aguardando atendimento" (e SAI do
  # filtro "IA", porque já está na hora de um humano), SEM virar "não atribuída" (ela TEM
  # dono: a IA). Some de "Aguardando atendimento" quando um humano assume (atribuição),
  # responde (A2c) ou a conversa resolve — o concern limpa o marcador nesses casos.
  #
  # Sem round-robin / auto-assign de humano: com o espelho captain presente, o A2b já
  # bloqueia o auto-assign de time, então a conversa não é empurrada pra um humano ausente.
  def trigger_handoff(conversation, _reason, team_id = nil)
    # Abre a conversa + dispara eventos. NÃO solta o espelho — a IA continua dona/respondendo.
    conversation.bot_handoff!

    # Time + marcador "aguardando humano" no MESMO save. Espelho captain presente => o A2b
    # impede o auto-assign de time, então o time é só roteamento (pra fila do setor certo).
    team = resolve_team(conversation, team_id)
    attrs = (conversation.custom_attributes || {}).merge('aguardando_humano_desde' => Time.current.iso8601)
    update_attrs = { custom_attributes: attrs }
    update_attrs[:team] = team if team
    conversation.update!(update_attrs)

    # Motor de Distribuição (F1): se o time tem política modo=rodizio, EMPURRA a conversa
    # pro consultor certo (continuidade/rodízio) em vez de deixá-la na fila "Aguardando
    # atendimento". Sem política / modo off/online => no-op (segue o pull atual). A
    # atribuição solta o espelho e limpa o marcador que acabamos de setar — o "aguardando"
    # é transitório no modo push (ver docs/MOTOR-DISTRIBUICAO.md §10.4/§10.7).
    Spx::Distribuicao::DistribuirService.new(conversation).call

    # Send out of office message if applicable (since template messages were suppressed while Captain was handling)
    send_out_of_office_message_if_applicable(conversation)
  end

  # LLM pode alucinar id — validar SEMPRE na conta. Se o LLM não passar um time válido,
  # cai no time do PRÓPRIO agente (config['team_id']) — assim a conversa nunca fica sem
  # fila/setor (ex.: handoff de pedido vago "falar com humano", sem time explícito).
  #
  # Override por conta (PRECEDÊNCIA): enquanto o rodízio (Motor de Distribuição) não está
  # ligado, TODO handoff cai num time ÚNICO de recepção — a recepção humana (ex.: Maria/Tozi)
  # vê tudo em "Aguardando atendimento" e distribui na mão. Setado em
  # account.custom_attributes['handoff_team_id']. Quando o Motor entrar, remove-se o override
  # e o handoff volta a rotear por setor (team_id/config) pro Motor distribuir automaticamente.
  def resolve_team(conversation, team_id)
    override = handoff_team_override(conversation.account)
    return override if override

    explicit = team_id.present? ? conversation.account.teams.find_by(id: team_id) : nil
    return explicit if explicit

    default_id = (@assistant.config || {})['team_id']
    default_id.present? ? conversation.account.teams.find_by(id: default_id) : nil
  end

  def handoff_team_override(account)
    tid = account.custom_attributes&.dig('handoff_team_id')
    tid.present? ? account.teams.find_by(id: tid) : nil
  end

  def send_out_of_office_message_if_applicable(conversation)
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
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
