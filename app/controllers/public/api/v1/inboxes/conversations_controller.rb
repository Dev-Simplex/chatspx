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
    # Caminho rápido (WAHA): se o webhook trouxer payload.ack, atualiza o status da mensagem direto.
    # Caso contrário cai no fallback de polling/bulk mark.
    if waha_ack_params_present?
      handle_waha_ack_status_update
      return head :ok
    end

    @conversation.contact_last_seen_at = DateTime.now.utc
    @conversation.save!

    if waha_inbox?
      ::Waha::MessageStatusSyncJob.perform_later(@conversation.id)
    else
      ::Conversations::UpdateMessageStatusJob.perform_later(@conversation.id, @conversation.contact_last_seen_at)
    end

    head :ok
  end

  private

  def waha_inbox?
    @conversation&.inbox&.waha_session_name.present?
  end

  def waha_ack_params_present?
    waha_inbox? && params.dig(:payload, :ack).present?
  end

  def handle_waha_ack_status_update
    waha_message_id = params.dig(:payload, :id)
    ack = params.dig(:payload, :ack).to_i
    status = waha_ack_to_chatwoot_status(ack)
    return if waha_message_id.blank? || status.blank?

    message = @conversation.messages.find_by(source_id: waha_message_id)
    return unless message

    # ack = -1 is WAHA's own send-error signal (positive evidence of failure);
    # surface it as 'failed'. The StatusUpdateService guard blocks
    # delivered/read → failed, so a late error ack never overrides a delivery.
    external_error = status == 'failed' ? 'WhatsApp (WAHA) reported a send error' : nil
    Messages::StatusUpdateService.new(message, status, external_error).perform
  end

  def waha_ack_to_chatwoot_status(ack)
    { -1 => 'failed', 1 => 'sent', 2 => 'delivered', 3 => 'read', 4 => 'read' }[ack]
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
