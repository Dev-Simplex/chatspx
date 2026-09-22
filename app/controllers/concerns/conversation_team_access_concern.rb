# Isolamento por time (regra do fork): conversa que pertence a um time só é
# acessível a quem é daquele time. Admin, AgentBot e o próprio assignee passam.
#
# Vivia solto no ConversationsController, então valia só para a conversa em si:
# `GET /conversations/:id` dava 403 enquanto `GET /conversations/:id/messages`
# devolvia 200 com o conteúdo do outro time — a ConversationPolicy aprova por
# ACESSO À CAIXA, que o agente de fora tem. Virou concern para que os
# sub-recursos (mensagens, etiquetas, participantes, funil...) fechem pela mesma
# regra, em um lugar só.
module ConversationTeamAccessConcern
  extend ActiveSupport::Concern

  private

  def authorize_team_access
    return if team_access_exempt?

    validate_team_param_access if params[:team_id].present?
    return if performed?

    # Bloqueia quem não é membro do time da conversa
    return if team_member?

    render json: { error: I18n.t('conversations.team_access.forbidden') }, status: :forbidden
  end

  # Mesma regra do guard, para quem precisa PERGUNTAR em vez de responder 403 na
  # hora: o `create` não passa pelo before_action (é CONVERSATIONLESS_ACTION) e
  # ainda assim pode acabar com uma conversa de outro time nas mãos, quando o
  # ConversationBuilder reusa a conversa que já existe do contato na caixa.
  def team_access_blocked?
    !team_access_exempt? && !team_member?
  end

  def team_member?
    Current.user.teams.exists?(id: @conversation.team_id)
  end

  def team_access_exempt?
    return true if Current.user.is_a?(AgentBot)
    return true if Current.user.administrator?
    return true if @conversation.team_id.nil?
    # Atribuição implica acesso: o assignee sempre alcança a própria conversa
    return true if @conversation.assignee_id == Current.user&.id
    # Supervisão de time (D2): quem supervisiona o time da conversa passa como se
    # fosse membro. Usa o account_id da conversa (e não Current.account) porque o
    # concern também roda em sub-recursos onde Current pode não estar populado.
    return true if TeamSupervision.supervises?(Current.user, @conversation.team_id, @conversation.account_id)

    false
  end

  # Hook. Só quem trata `team_id` como "estou vendo a conversa no contexto do
  # time X" valida o parâmetro (ConversationsController). Nos sub-recursos o
  # `team_id` significa outra coisa — em `assignments` é o time DE DESTINO —, e
  # validar aqui exigiria que o destino fosse o time atual, ou seja, quebraria
  # justamente mover a conversa de time.
  def validate_team_param_access; end
end
