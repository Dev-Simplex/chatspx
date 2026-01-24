class Api::V1::Accounts::Messages::ForwardController < Api::V1::Accounts::BaseController
  before_action :set_message

  def create
    result = Messages::ForwardService.new(
      message: @message,
      target_conversation_ids: permitted_params[:conversation_ids],
      user: Current.user
    ).perform

    if result[:success]
      render json: {
        success: true,
        forwarded_count: result[:forwarded_messages].count,
        messages: result[:forwarded_messages].map { |msg| message_json(msg) }
      }, status: :created
    else
      render json: {
        success: false,
        errors: result[:errors]
      }, status: :unprocessable_entity
    end
  end

  private

  def set_message
    @message = Current.account.messages.find(params[:id] || params[:message_id])
  end

  def permitted_params
    params.require(:forward).permit(conversation_ids: [])
  end

  def message_json(message)
    {
      id: message.id,
      conversation_id: message.conversation.display_id,
      content: message.content,
      created_at: message.created_at,
      forwarded: message.forwarded
    }
  end
end
