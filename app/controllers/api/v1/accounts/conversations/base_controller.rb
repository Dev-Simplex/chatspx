class Api::V1::Accounts::Conversations::BaseController < Api::V1::Accounts::BaseController
  include ConversationTeamAccessConcern
  include AgentConversationAccessConcern

  before_action :conversation
  # A ConversationPolicy aprova por acesso à CAIXA, então `show?` sozinho deixava
  # os sub-recursos (mensagens, etiquetas, participantes, funil...) abertos para
  # quem não é do time da conversa — enquanto a conversa em si dava 403. Este
  # guard fecha essa porta com a mesma regra do ConversationsController.
  before_action :authorize_team_access
  # E o isolamento por AGENTE (inbox isolado): só o dono acessa os sub-recursos.
  before_action :authorize_agent_conversation_access

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end
end
