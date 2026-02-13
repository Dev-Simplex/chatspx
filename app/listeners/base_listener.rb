class BaseListener
  include Singleton

  def extract_conversation_and_account(event)
    conversation = event.data[:conversation]
    [conversation, conversation.account]
  end

  def extract_notification_and_account(event)
    notification = event.data[:notification]
    notification_finder = NotificationFinder.new(notification.user, notification.account)
    unread_count = notification_finder.unread_count
    count = notification_finder.count
    [notification, notification.account, unread_count, count]
  end

  def extract_message_and_account(event)
    message = event.data[:message]
    [message, message.account]
  end

  def extract_contact_and_account(event)
    contact = event.data[:contact]
    [contact, contact.account]
  end

  def extract_inbox_and_account(event)
    inbox = event.data[:inbox]
    [inbox, inbox.account]
  end

  def extract_changed_attributes(event)
    changed_attributes = event.data[:changed_attributes]

    return if changed_attributes.blank?

    # Normal format from previous_changes: { attr => [old_val, new_val] }
    # mark_as_unread! sends { 'agent_last_seen_at' => true, 'assignee_last_seen_at' => true }; avoid v[0]/v[1] on non-array
    changed_attributes.map do |k, v|
      prev, curr = v.is_a?(Array) && v.size >= 2 ? [v[0], v[1]] : [nil, v]
      { k => { previous_value: prev, current_value: curr } }
    end
  end
end
