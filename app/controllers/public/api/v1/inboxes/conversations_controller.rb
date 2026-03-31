class Public::Api::V1::Inboxes::ConversationsController < Public::Api::V1::InboxesController
  include Events::Types
  before_action :set_conversation, only: [:toggle_typing, :update_last_seen, :show, :toggle_status]

  def index
    @conversations = @contact_inbox.hmac_verified? ? @contact_inbox.contact.conversations : @contact_inbox.conversations
  end

  def show; end

  def create
    @conversation = create_conversation
  end

  def toggle_status
    # Check if the conversation is already resolved to prevent redundant operations
    return if @conversation.resolved?

    # Assign the conversation's contact as the resolver
    # This step attributes the resolution action to the contact involved in the conversation
    # If this assignment is not made, the system implicitly becomes the resolver by default
    Current.contact = @conversation.contact

    # Update the conversation's status to 'resolved' to reflect its closure
    @conversation.status = :resolved
    @conversation.save!
  end

  def toggle_typing
    case params[:typing_status]
    when 'on'
      trigger_typing_event(CONVERSATION_TYPING_ON)
    when 'off'
      trigger_typing_event(CONVERSATION_TYPING_OFF)
    end
    head :ok
  end

  def update_last_seen
    # Per-message status update when WAHA sends ack payload — skip bulk update
    if waha_ack_params_present?
      handle_waha_ack_status_update
      return head :ok
    end

    # Bulk update (existing behavior for non-WAHA calls)
    @conversation.contact_last_seen_at = DateTime.now.utc
    @conversation.save!
    ::Conversations::UpdateMessageStatusJob.perform_later(@conversation.id, @conversation.contact_last_seen_at)
    head :ok
  end

  private

  def waha_ack_params_present?
    params.dig(:payload, :ack).present?
  end

  def handle_waha_ack_status_update
    waha_message_id = params.dig(:payload, :id)
    ack = params.dig(:payload, :ack).to_i
    status = waha_ack_to_chatwoot_status(ack)

    return if waha_message_id.blank? || status.blank?

    message = @conversation.messages.find_by(source_id: waha_message_id)
    Messages::StatusUpdateService.new(message, status).perform if message
  end

  def waha_ack_to_chatwoot_status(ack)
    { 1 => 'sent', 2 => 'delivered', 3 => 'read', 4 => 'read' }[ack]
  end

  def set_conversation
    @conversation = if @contact_inbox.hmac_verified?
                      @contact_inbox.contact.conversations.find_by!(display_id: params[:id])
                    else
                      @contact_inbox.conversations.find_by!(display_id: params[:id])
                    end
  end

  def create_conversation
    ConversationBuilder.new(params: conversation_params, contact_inbox: @contact_inbox).perform
  end

  def trigger_typing_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: @conversation, user: @conversation.contact)
  end

  def conversation_params
    params.permit(custom_attributes: {})
  end
end
