class Api::V1::Accounts::ProactiveMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  # Bloco 5.20 — UMA chamada: destinatario + inbox + conteudo. Quem dispara nao precisa saber o que
  # e contact_inbox nem display_id, e nao ha estado intermediario para vazar no meio do caminho.
  def create
    result = Messages::ProactiveDispatchService.new(
      account: Current.account,
      inbox: @inbox,
      sender: Current.user,
      params: permitted_params
    ).perform

    return render json: { error: result.error }, status: result.status unless result.success?

    render json: {
      conversation_id: result.conversation.display_id,
      message_id: result.message.id,
      contact_id: result.conversation.contact_id,
      conversation_status: result.conversation.status
    }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def permitted_params
    params.permit(:inbox_id, :identifier, :email, :phone_number, :content,
                  :create_conversation_without_contact_reply, :allow_unverified_contact)
  end
end
