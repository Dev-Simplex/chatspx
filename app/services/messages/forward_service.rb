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

  # Reuse the contact's existing conversation on this inbox instead of creating a new one for every
  # forward. The dashboard forwards by firing one request per message in parallel, so without this
  # several messages sent to the same contact each spawned their own conversation; forwarding to a
  # contact whose previous conversation was already resolved also created a fresh one each time.
  #
  # We take the same Redis lock key ConversationBuilder uses (so a forward and a regular incoming
  # message for the same contact can't race each other) and reuse the contact's most recent
  # conversation on the inbox, reopening it when needed.
  def find_or_create_conversation_for_contact(contact)
    inbox = message.inbox
    contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
                    ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)

    with_conversation_lock(inbox, contact) do
      reusable_conversation(inbox, contact) || create_conversation(inbox, contact, contact_inbox)
    end
  end

  def with_conversation_lock(inbox, contact)
    lock_key = "conv_builder:#{inbox.id}:#{contact.id}"
    # Short TTL (below the rack-timeout) so a request killed mid-flight can't hold the lock for long.
    acquired = Redis::Alfred.set(lock_key, '1', nx: true, ex: 10)
    # Another create for this contact is already in flight; reuse what it produces instead of racing.
    return reusable_conversation(inbox, contact) unless acquired

    begin
      yield
    ensure
      Redis::Alfred.delete(lock_key)
    end
  end

  # Most recent conversation for the contact on this inbox (across contact_inboxes), preferring a
  # non-resolved one and falling back to the latest of any status, reopened so the forward shows up.
  def reusable_conversation(inbox, contact)
    base = inbox.conversations.where(contact_id: contact.id)
    conversation = base.where.not(status: :resolved).order(created_at: :desc).first ||
                   base.order(created_at: :desc).first
    return unless conversation

    conversation.update!(status: :open) if conversation.resolved?
    conversation
  end

  def create_conversation(inbox, contact, contact_inbox)
    Conversation.create!(account: message.account, inbox: inbox, contact: contact,
                         contact_inbox: contact_inbox, assignee: user, status: :open)
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
