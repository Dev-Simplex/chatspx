class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    with_conversation_lock do
      look_up_exising_conversation || create_new_conversation
    end
  end

  private

  def with_conversation_lock
    lock_key = "conv_builder:#{@contact_inbox.inbox_id}:#{@contact_inbox.contact_id}"
    acquired = Redis::Alfred.set(lock_key, '1', nx: true, ex: 15)

    unless acquired
      # Another request is creating a conversation — wait briefly and return existing
      sleep(0.5)
      return look_up_exising_conversation
    end

    begin
      yield
    ensure
      Redis::Alfred.delete(lock_key)
    end
  end

  def look_up_exising_conversation
    return find_contact_conversation_in_inbox if @contact_inbox.inbox.lock_to_single_conversation?
    return last_open_conversation if waha_api_inbox?

    nil
  end

  # Lookup by contact+inbox (not just contact_inbox) to handle multiple contact_inboxes for the same contact
  # Prioritize non-resolved conversations, fallback to most recent of any status
  def find_contact_conversation_in_inbox
    base = ::Conversation.where(inbox_id: @contact_inbox.inbox_id, contact_id: @contact_inbox.contact_id)
    base.where.not(status: :resolved).order(created_at: :desc).first || base.order(created_at: :desc).first
  end

  def waha_api_inbox?
    @contact_inbox.inbox.channel_type == 'Channel::Api' && @contact_inbox.inbox.waha_session_name.present?
  end

  def last_open_conversation
    @contact_inbox.conversations.where.not(status: :resolved).last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end
end
