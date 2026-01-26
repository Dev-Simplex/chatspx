class Messages::ForwardService
  pattr_initialize [:message!, :target_conversation_ids!, :user!]

  def perform
    return { success: false, error: 'No target conversations provided' } if target_conversation_ids.blank?
    return { success: false, error: 'Too many conversations' } if target_conversation_ids.size > 10

    forwarded_messages = []
    errors = []

    target_conversation_ids.each do |conversation_id|
      result = forward_to_conversation(conversation_id)
      if result[:success]
        forwarded_messages << result[:message]
      else
        errors << { conversation_id: conversation_id, error: result[:error] }
      end
    end

    {
      success: errors.empty?,
      forwarded_messages: forwarded_messages,
      errors: errors
    }
  end

  private

  def forward_to_conversation(conversation_id)
    target_conversation = find_conversation(conversation_id)
    return { success: false, error: 'Conversation not found' } unless target_conversation
    return { success: false, error: 'No permission' } unless can_access_conversation?(target_conversation)

    forwarded_message = create_forwarded_message(target_conversation)

    if forwarded_message.persisted?
      { success: true, message: forwarded_message }
    else
      { success: false, error: forwarded_message.errors.full_messages.join(', ') }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def find_conversation(conversation_id)
    message.account.conversations.find_by(display_id: conversation_id) ||
      message.account.conversations.find_by(id: conversation_id)
  end

  def can_access_conversation?(conversation)
    # Check if user has access to the conversation
    # For now, just check if conversation belongs to the same account
    conversation.account_id == message.account_id
  end

  def create_forwarded_message(target_conversation)
    new_message_params = {
      account_id: message.account_id,
      inbox_id: target_conversation.inbox_id,
      conversation_id: target_conversation.id,
      message_type: :outgoing,
      content: message.content,
      content_type: message.content_type,
      content_attributes: message.content_attributes.except('deleted'),
      sender: user,
      forwarded: true,
      forwarded_from_message_id: message.id,
      private: false
    }

    new_message = target_conversation.messages.build(new_message_params)

    # Copy attachments if present
    if message.attachments.any?
      message.attachments.each do |attachment|
        new_attachment = new_message.attachments.build(
          account_id: message.account_id,
          file_type: attachment.file_type,
          extension: attachment.extension,
          external_url: attachment.external_url,
          fallback_title: attachment.fallback_title,
          coordinates_lat: attachment.coordinates_lat,
          coordinates_long: attachment.coordinates_long,
          meta: attachment.meta
        )

        new_attachment.file.attach(attachment.file.blob) if attachment.file.attached?
      end
    end

    new_message.save
    new_message
  end
end

