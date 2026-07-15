# Encaminha uma conversa da IA para um ATENDENTE HUMANO (Modelo A): abre a conversa,
# roteia pro time certo e marca `aguardando_humano_desde` — a IA silencia e a conversa
# entra em "Aguardando atendimento", SEM soltar o espelho captain (a IA segue dona até
# um humano PUXAR a atribuição). Extraído do HandoffTool pra ter uma fonte única:
# além do handoff pedido pelo agente (tool://handoff), o FollowupJob escala pra humano
# quando as cutucadas in-window esgotam.
class Captain::Conversation::HumanHandoffService
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

    # Motor de Distribuição: se o time tem política modo=rodizio, empurra a conversa pro
    # consultor certo em vez de deixá-la na fila "Aguardando atendimento". Sem política => no-op.
    Spx::Distribuicao::DistribuirService.new(@conversation).call

    send_out_of_office_message_if_applicable
  end

  private

  # post the reason as a private note (dossiê pro humano que assumir)
  def create_handoff_note
    @conversation.messages.create!(
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
  def resolve_team
    explicit = @team_id.present? ? @conversation.account.teams.find_by(id: @team_id) : nil
    return explicit if explicit

    default_id = (@assistant&.config || {})['team_id']
    default_id.present? ? @conversation.account.teams.find_by(id: default_id) : nil
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end
end
