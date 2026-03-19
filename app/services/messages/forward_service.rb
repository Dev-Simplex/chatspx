class Messages::ForwardService
  pattr_initialize [:message!, :target_conversation_ids!, :user!, { target_contact_ids: [] }]

  def perform
    return { success: false, error: 'No targets provided' } if total_targets.zero?
    return { success: false, error: 'Too many targets' } if total_targets > 10

    forward_to_conversations
    forward_to_contacts

    { success: @errors.empty?, forwarded_messages: @forwarded_messages, errors: @errors }
  end

  private

  def total_targets
    target_conversation_ids.to_a.size + target_contact_ids.to_a.size
  end

  def forward_to_conversations
    @forwarded_messages = []
    @errors = []
    target_conversation_ids.each { |id| process_forward(forward_to_conversation(id), conversation_id: id) }
  end

  def forward_to_contacts
    target_contact_ids.to_a.each { |id| process_forward(forward_to_contact(id), contact_id: id) }
  end

  def process_forward(result, context = {})
    if result[:success]
      @forwarded_messages << result[:message]
    else
      @errors << context.merge(error: result[:error])
    end
  end

  def forward_to_conversation(conversation_id)
    target_conversation = find_conversation(conversation_id)
    return error_result('Conversation not found') unless target_conversation
    return error_result('No permission') unless can_access_conversation?(target_conversation)

    build_forward_result(target_conversation)
  rescue StandardError => e
    error_result(e.message)
  end

  def forward_to_contact(contact_id)
    contact = message.account.contacts.find_by(id: contact_id)
    return error_result('Contact not found') unless contact

    target_conversation = find_or_create_conversation_for_contact(contact)
    return error_result('Could not create conversation') unless target_conversation

    build_forward_result(target_conversation)
  rescue StandardError => e
    error_result(e.message)
  end

  def build_forward_result(target_conversation)
    forwarded_message = create_forwarded_message(target_conversation)
    return { success: true, message: forwarded_message } if forwarded_message.persisted?

    error_result(forwarded_message.errors.full_messages.join(', '))
  end

  def error_result(msg)
    { success: false, error: msg }
  end

  def find_or_create_conversation_for_contact(contact)
    inbox = message.inbox
    contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id)
    existing = find_existing_conversation(contact_inbox)
    return existing if existing

    contact_inbox ||= ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
    Conversation.create!(account: message.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                         assignee: user, status: :open)
  end

  def find_existing_conversation(contact_inbox)
    return unless contact_inbox

    contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
  end

  def find_conversation(conversation_id)
    message.account.conversations.find_by(display_id: conversation_id) ||
      message.account.conversations.find_by(id: conversation_id)
  end

  def can_access_conversation?(conversation)
    conversation.account_id == message.account_id
  end

  def create_forwarded_message(target_conversation)
    new_message = target_conversation.messages.build(forwarded_message_params(target_conversation))
    copy_attachments(new_message)
    new_message.save
    new_message
  end

  def forwarded_message_params(target_conversation)
    {
      account_id: message.account_id, inbox_id: target_conversation.inbox_id,
      conversation_id: target_conversation.id, message_type: :outgoing,
      content: message.content, content_type: message.content_type,
      content_attributes: message.content_attributes.except('deleted'),
      sender: user, forwarded: true, forwarded_from_message_id: message.id, private: false
    }
  end

  def copy_attachments(new_message)
    return unless message.attachments.any?

    message.attachments.each do |attachment|
      new_att = new_message.attachments.build(
        account_id: message.account_id, file_type: attachment.file_type, extension: attachment.extension,
        external_url: attachment.external_url, fallback_title: attachment.fallback_title,
        coordinates_lat: attachment.coordinates_lat, coordinates_long: attachment.coordinates_long, meta: attachment.meta
      )
      new_att.file.attach(attachment.file.blob) if attachment.file.attached?
    end
  end
end
