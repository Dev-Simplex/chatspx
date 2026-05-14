# frozen_string_literal: true

# Endpoints to manage the collective pinned messages list of a conversation.
#
# POST  /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/pin
# DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/pin
#
# Pin é coletivo (todos os agents do account compartilham a lista), com
# cap de 3 entradas. 422 quando o limite é atingido.
class Api::V1::Accounts::Conversations::Messages::PinController < Api::V1::Accounts::Conversations::BaseController
  def create
    pinned_ids = service.add
    render json: payload(pinned_ids)
  rescue Messages::PinService::LimitReached => e
    render json: { error: e.message, pinned_message_ids: Messages::PinService.pinned_ids(@conversation) },
           status: :unprocessable_entity
  rescue Messages::PinService::NotFound
    render json: { error: 'message_not_found' }, status: :not_found
  end

  def destroy
    pinned_ids = service.remove
    render json: payload(pinned_ids)
  rescue Messages::PinService::NotFound
    render json: { error: 'message_not_found' }, status: :not_found
  end

  private

  def service
    @service ||= Messages::PinService.new(
      conversation: @conversation,
      message_id: params[:id]
    )
  end

  def payload(pinned_ids)
    {
      conversation_id: @conversation.display_id,
      pinned_message_ids: pinned_ids
    }
  end
end
