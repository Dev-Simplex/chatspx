# Encaminha uma conversa da IA para um ATENDENTE HUMANO (Modelo A): abre a conversa,
# roteia pro time certo e marca `aguardando_humano_desde` — a IA silencia e a conversa
# entra em "Aguardando atendimento", SEM soltar o espelho captain (a IA segue dona até
# um humano PUXAR a atribuição). Extraído do HandoffTool pra ter uma fonte única:
# além do handoff pedido pelo agente (tool://handoff), o FollowupJob escala pra humano
# quando as cutucadas in-window esgotam.
class Captain::Conversation::HumanHandoffService
  attr_reader :handoff_note

  def initialize(conversation:, assistant:, reason: nil, team_id: nil)
    @conversation = conversation
    @assistant = assistant
    @reason = reason
    @team_id = team_id
  end

  def perform
    # Idempotente: se a conversa JÁ está aguardando humano, não refaz o handoff (senão
    # gera nota/dossiê duplicado e reseta o marcador a cada passagem).
    return if @conversation.custom_attributes&.dig('aguardando_humano_desde').present?

    create_handoff_note if @reason.present?

    # Abre a conversa + dispara eventos. NÃO solta o espelho — a IA continua dona/respondendo.
    @conversation.bot_handoff!

    # Time + marcador "aguardando humano" no MESMO save. Com o espelho captain presente,
    # o auto-assign de time fica bloqueado, então o time é só roteamento (fila do setor).
    team = resolve_team
    attrs = (@conversation.custom_attributes || {}).merge('aguardando_humano_desde' => Time.current.iso8601)
    update_attrs = { custom_attributes: attrs }
    update_attrs[:team] = team if team
    @conversation.update!(update_attrs)

    registrar_handoff(team)

    # Motor de Distribuição: se o time tem política modo=rodizio, empurra a conversa pro
    # consultor certo em vez de deixá-la na fila "Aguardando atendimento". Sem política => no-op.
    Spx::Distribuicao::DistribuirService.new(@conversation).call

    send_out_of_office_message_if_applicable
  end

  private

  # Sinal DURÁVEL de que a IA passou o bastão.
  #
  # `handoff` estava declarado em EVENT_TYPES desde sempre e NUNCA era escrito: o HandoffTool
  # só chamava `log_tool_usage`, que vai pro Rails.logger e não cria registro. Sem isto, a
  # reconstituição do desfecho (Captain::EpisodeOutcomeService) fica refém da cobertura do F2
  # e do `aguardando_humano_desde`, que é TRANSITÓRIO — limpo quando o humano assume, medido
  # em 2 conversas de 20.170 na conta 6. Estado não serve de histórico.
  #
  # Fica AQUI, e não no HandoffTool, porque este service é a fonte única: os 6 call sites
  # (tool, transferência entre agentes, escalada do follow-up, safety-nets do
  # ResponseBuilderJob) passam por ele. Logar no tool cobriria um caminho só.
  #
  # Depois do `update!` pra o payload já refletir o time resolvido; e rescue-wrapped porque
  # registrar NUNCA pode derrubar comportamento — foi assim que o safety-net de handoff e o
  # backstop anti-repetição morreram calados em produção.
  def registrar_handoff(team)
    # captain_assistant_id é NOT NULL e o assistant pode chegar nil (o resolve_team já o trata
    # com `&.`). Sai explícito em vez de estourar no create! e cair no rescue — mesmo critério
    # do log_mirror_event: sem assistant, está fora da telemetria captain.
    return if @assistant.blank?

    Captain::AssistantLog.create!(
      captain_assistant: @assistant,
      conversation: @conversation,
      event_type: 'handoff',
      payload: { 'team_id' => team&.id, 'com_dossie' => @reason.present? }
    )
  rescue StandardError => e
    Rails.logger.warn("[Captain] assistant_log de handoff falhou conv=#{@conversation&.id}: #{e.message}")
  end

  # post the reason as a private note (dossiê pro humano que assumir)
  def create_handoff_note
    @handoff_note = @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: @conversation.account,
      inbox: @conversation.inbox,
      content: @reason
    )
  end

  # LLM pode alucinar id — validar SEMPRE na conta. Sem time válido, cai no time do
  # PRÓPRIO agente (config['team_id']) — a conversa nunca fica sem fila/setor.
  #
  # Validar só por conta aceitava QUALQUER time do cadastro, e é por aí que o modelo mandava
  # cliente de uma marca pro time de outra. Aqui a conta pode restringir o destino
  # (`Account#handoff_teams`); sem a chave configurada, `handoff_teams` são todos os times e
  # nada muda. Este é o ponto que FECHA — a enumeração no tool é só orientação.
  def resolve_team
    explicit = @team_id.present? ? allowed_team(@team_id) : nil
    return explicit if explicit

    default_id = (@assistant&.config || {})['team_id']
    default_id.present? ? allowed_team(default_id) : nil
  end

  # Time recusado se comporta como id inválido: NÃO derruba o handoff. Cai no time padrão do
  # agente e, se ele também estiver fora, o handoff segue SEM time — caminho que já existe
  # (`update_attrs[:team] = team if team`) e não quebra nada, enquanto falhar deixaria o
  # cliente ouvindo "uma pessoa vai assumir" sem ninguém acionado.
  #
  # Loga só quando o id EXISTE na conta mas está fora da allowlist: sem isso a recusa fica
  # indistinguível de alucinação do modelo, e "por que foi pro time errado?" vira adivinhação.
  def allowed_team(id)
    account = @conversation.account
    team = account.handoff_teams.find_by(id: id)
    if team.nil? && account.teams.exists?(id: id)
      Rails.logger.info("[Captain][handoff] time #{id} fora da allowlist da conta #{account.id} — conv=#{@conversation.id}")
    end
    team
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end
end
