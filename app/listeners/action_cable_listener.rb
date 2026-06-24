class ActionCableListener < BaseListener # rubocop:disable Metrics/ClassLength
  include Events::Types

  def notification_created(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_CREATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_updated(event)
    notification, account, unread_count, count = extract_notification_and_account(event)
    tokens = [event.data[:notification].user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_UPDATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
  end

  def notification_deleted(event)
    notification_data = event.data[:notification_data]

    user = User.find_by(id: notification_data[:user_id])
    account = Account.find_by(id: notification_data[:account_id])
    return if user.blank? || account.blank?

    notification_finder = NotificationFinder.new(user, account)
    tokens = [user.pubsub_token]
    broadcast(account, tokens, NOTIFICATION_DELETED, {
                notification: { id: notification_data[:id] },
                unread_count: notification_finder.unread_count,
                count: notification_finder.count
              })
  end

  def account_cache_invalidated(event)
    account = event.data[:account]
    tokens = user_tokens(account, account.agents)

    broadcast(account, tokens, ACCOUNT_CACHE_INVALIDATED, {
                cache_keys: event.data[:cache_keys]
              })
  end

  def message_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members) +
             participant_tokens(conversation) +
             contact_tokens(conversation.contact_inbox, message)

    broadcast(account, tokens, MESSAGE_CREATED, message.push_event_data)
  end

  def message_updated(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members) +
             participant_tokens(conversation) +
             contact_tokens(conversation.contact_inbox, message)

    broadcast(account, tokens, MESSAGE_UPDATED, message.push_event_data.merge(previous_changes: event.data[:previous_changes]))
  end

  def first_reply_created(event)
    message, account = extract_message_and_account(event)
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, FIRST_REPLY_CREATED, message.push_event_data)
  end

  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members) + contact_inbox_tokens(conversation.contact_inbox)

    broadcast(account, tokens, CONVERSATION_CREATED, conversation.push_event_data)
  end

  def conversation_read(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, CONVERSATION_READ, conversation.push_event_data)
  end

  def conversation_status_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members) + contact_inbox_tokens(conversation.contact_inbox)

    broadcast(account, tokens, CONVERSATION_STATUS_CHANGED, conversation.push_event_data)
  end

  def conversation_updated(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members) + contact_inbox_tokens(conversation.contact_inbox)

    broadcast(account, tokens, CONVERSATION_UPDATED, conversation.push_event_data)
  end

  def conversation_typing_on(event)
    conversation = event.data[:conversation]
    account = conversation.account
    user = event.data[:user]
    tokens = typing_event_listener_tokens(account, conversation, user)

    broadcast(
      account,
      tokens,
      CONVERSATION_TYPING_ON,
      conversation: { id: conversation.display_id },
      user: { id: user.id, name: user.name, type: user.is_a?(Contact) ? 'contact' : 'user' },
      is_private: event.data[:is_private] || false
    )
  end

  def conversation_typing_off(event)
    conversation = event.data[:conversation]
    account = conversation.account
    user = event.data[:user]
    tokens = typing_event_listener_tokens(account, conversation, user)

    broadcast(
      account,
      tokens,
      CONVERSATION_TYPING_OFF,
      conversation: { id: conversation.display_id },
      user: { id: user.id, name: user.name, type: user.is_a?(Contact) ? 'contact' : 'user' },
      is_private: event.data[:is_private] || false
    )
  end

  def assignee_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, ASSIGNEE_CHANGED, conversation.push_event_data)
  end

  # Kanban v2 (Fase 4): broadcast a card's stage move so other open boards
  # relocate it live. Goes to every user of the account (board is account-wide).
  def funnel_item_moved(event)
    funnel_item = event.data[:funnel_item]
    account = funnel_item&.funnel&.account
    return if account.blank?

    tokens = account.users.pluck(:pubsub_token)
    broadcast(account, tokens, FUNNEL_ITEM_MOVED, funnel_item.push_event_data)
  end

  def team_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, TEAM_CHANGED, conversation.push_event_data)
  end

  def conversation_contact_changed(event)
    conversation, account = extract_conversation_and_account(event)
    tokens = user_tokens(account, conversation.inbox.members)

    broadcast(account, tokens, CONVERSATION_CONTACT_CHANGED, conversation.push_event_data)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_CREATED, contact.push_event_data)
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_UPDATED, contact.push_event_data)
  end

  def contact_merged(event)
    contact, account = extract_contact_and_account(event)
    broadcast(account, [account_token(account)], CONTACT_MERGED, contact.push_event_data)
  end

  def contact_deleted(event)
    contact_data = event.data[:contact_data]
    account = Account.find_by(id: contact_data[:account_id])
    return if account.blank?

    broadcast(account, [account_token(account)], CONTACT_DELETED, contact_data)
  end

  def conversation_mentioned(event)
    conversation, account = extract_conversation_and_account(event)
    user = event.data[:user]

    broadcast(account, [user.pubsub_token], CONVERSATION_MENTIONED, conversation.push_event_data)
  end

  # PR B1 — emoji reaction lifecycle. Broadcasts to the same audience as
  # `message_updated` (inbox members + admins + participants + contact),
  # so the panel and mobile clients converge on the same recipient set.
  def message_reaction_added(event)
    message, account = extract_message_and_account(event)
    reaction = event.data[:reaction]
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members) +
             participant_tokens(conversation) +
             contact_tokens(conversation.contact_inbox, message)

    broadcast(account, tokens, MESSAGE_REACTION_ADDED, {
                message_id: message.id,
                conversation_id: conversation.display_id,
                reaction: reaction.push_event_data
              })
  end

  def message_reaction_removed(event)
    message, account = extract_message_and_account(event)
    reaction = event.data[:reaction]
    conversation = message.conversation
    tokens = user_tokens(account, conversation.inbox.members) +
             participant_tokens(conversation) +
             contact_tokens(conversation.contact_inbox, message)

    broadcast(account, tokens, MESSAGE_REACTION_REMOVED, {
                message_id: message.id,
                conversation_id: conversation.display_id,
                reaction_id: reaction.id,
                emoji: reaction.emoji,
                user_id: reaction.user_id,
                user_type: reaction.user_type
              })
  end

  # PR B4 — broadcasts the updated user_settings node only to the owning user's tokens.
  # Other agents do NOT receive this event (per-user privacy: pinned/archived/muted/theme).
  def conversation_user_setting_changed(event)
    conversation = event.data[:conversation]
    user_id = event.data[:user_id]
    return if conversation.blank? || user_id.blank?

    user = User.find_by(id: user_id)
    return if user.blank?

    account = conversation.account
    tokens = [user.pubsub_token].compact

    payload = {
      conversation: { id: conversation.display_id },
      user_id: user.id,
      user_settings: conversation.user_setting_for(user_id)
    }

    broadcast(account, tokens, CONVERSATION_USER_SETTING_CHANGED, payload)
  end

  # PR G1 — broadcasts the pinned_message_ids array to ALL agents/admins of the inbox.
  # Pin é coletivo: todos os agents do account compartilham a lista (diferente do pin per-user de B4).
  def conversation_pin_added(event)
    broadcast_conversation_pin(event, CONVERSATION_PIN_ADDED)
  end

  def conversation_pin_removed(event)
    broadcast_conversation_pin(event, CONVERSATION_PIN_REMOVED)
  end

  private

  # PR G1 — shared payload for both pin_added and pin_removed.
  def broadcast_conversation_pin(event, event_name)
    conversation = event.data[:conversation]
    return if conversation.blank?

    account = conversation.account
    tokens = user_tokens(account, conversation.inbox.members)

    payload = {
      conversation: { id: conversation.display_id },
      message_id: event.data[:message_id],
      pinned_message_ids: event.data[:pinned_message_ids] || Messages::PinService.pinned_ids(conversation)
    }

    broadcast(account, tokens, event_name, payload)
  end

  def account_token(account)
    "account_#{account.id}"
  end

  def typing_event_listener_tokens(account, conversation, user)
    current_user_token = if user.is_a?(Contact)
                           conversation.contact_inbox.pubsub_token
                         elsif user.respond_to?(:pubsub_token)
                           user.pubsub_token
                         end

    tokens = user_tokens(account, conversation.inbox.members) + [conversation.contact_inbox.pubsub_token]
    current_user_token.present? ? tokens - [current_user_token] : tokens
  end

  def user_tokens(account, agents)
    inbox = agents.try(:proxy_association)&.owner
    agent_tokens = if inbox
                     Rails.cache.fetch("inbox:#{inbox.id}:member_pubsub_tokens", expires_in: 2.minutes,
                                                                                 race_condition_ttl: 10.seconds) do
                       agents.pluck(:pubsub_token)
                     end
                   else
                     agents.pluck(:pubsub_token)
                   end
    admin_tokens = Rails.cache.fetch(
      "account:#{account.id}:admin_pubsub_tokens",
      expires_in: 2.minutes,
      race_condition_ttl: 10.seconds
    ) do
      account.administrators.pluck(:pubsub_token)
    end
    (agent_tokens + admin_tokens).uniq
  end

  def participant_tokens(conversation)
    Rails.cache.fetch("conversation:#{conversation.id}:participant_tokens", expires_in: 30.seconds,
                                                                            race_condition_ttl: 5.seconds) do
      conversation.conversation_participants.joins(:user).pluck('users.pubsub_token')
    end
  end

  def contact_tokens(contact_inbox, message)
    return [] if message.private?
    return [] if message.activity?
    return [] if contact_inbox.nil?

    contact_inbox_tokens(contact_inbox)
  end

  def contact_inbox_tokens(contact_inbox)
    return [] if contact_inbox.nil?

    contact = contact_inbox.contact

    contact_inbox.hmac_verified? ? contact.contact_inboxes.where(hmac_verified: true).pluck(:pubsub_token) : [contact_inbox.pubsub_token]
  end

  def broadcast(account, tokens, event_name, data)
    return if tokens.blank?

    payload = data.merge(account_id: account.id)
    # So the frondend knows who performed the action.
    # Useful in cases like conversation assignment for generating a notification with assigner name.
    payload[:performer] = Current.user&.push_event_data if Current.user.present?

    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, payload)
  end
end

ActionCableListener.prepend_mod_with('ActionCableListener')
