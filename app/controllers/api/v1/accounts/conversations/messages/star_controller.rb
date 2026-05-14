# Dedicated controller for the star/unstar message endpoint.
# Splits the toggle behavior into explicit, idempotent verbs:
#   - POST   /messages/:message_id/star  -> create  (sets starred = true)
#   - DELETE /messages/:message_id/star  -> destroy (sets starred = false)
#
# Both actions are idempotent: calling POST on an already-starred message,
# or DELETE on an already-unstarred message, is a no-op that still returns
# 200 with the current state. The MESSAGE_UPDATED event is only dispatched
# when the persisted state actually changes, so subscribers (ActionCable,
# webhooks) are not spammed with redundant notifications.
#
# Pattern: mirrors the dedicated Messages::ReactionsController
# (see reactions_controller.rb) — Chatwoot uses per-action controllers
# for narrow, side-effect-heavy operations on messages.
class Api::V1::Accounts::Conversations::Messages::StarController < Api::V1::Accounts::Conversations::BaseController
  def create
    set_starred(true)
  end

  def destroy
    set_starred(false)
  end

  private

  def set_starred(value)
    changed = message.starred? != value
    message.update!(starred: value) if changed
    notify_message_updated if changed
    render json: { id: message.id, starred: message.starred }
  end

  def message
    @message ||= @conversation.messages.find(params[:message_id])
  end

  def notify_message_updated
    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_UPDATED,
      Time.zone.now,
      message: message,
      performed_by: Current.user
    )
  end
end
