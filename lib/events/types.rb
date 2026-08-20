# frozen_string_literal: true

module Events::Types
  ### Installation Events ###
  # account events
  ACCOUNT_CREATED = 'account.created'
  ACCOUNT_CACHE_INVALIDATED = 'account.cache_invalidated'

  #### Account Events ###
  # campaign events
  CAMPAIGN_TRIGGERED = 'campaign.triggered'

  # channel events
  WEBWIDGET_TRIGGERED = 'webwidget.triggered'

  # conversation events
  CONVERSATION_CREATED = 'conversation.created'
  CONVERSATION_UPDATED = 'conversation.updated'
  CONVERSATION_DELETED = 'conversation.deleted'
  CONVERSATION_READ = 'conversation.read'
  CONVERSATION_BOT_HANDOFF = 'conversation.bot_handoff'
  # FIXME: deprecate the opened and resolved events in future in favor of status changed event.
  CONVERSATION_OPENED = 'conversation.opened'
  CONVERSATION_RESOLVED = 'conversation.resolved'
  CONVERSATION_CAPTAIN_INFERENCE_RESOLVED = 'conversation.captain_inference_resolved'
  CONVERSATION_CAPTAIN_INFERENCE_HANDOFF = 'conversation.captain_inference_handoff'

  CONVERSATION_STATUS_CHANGED = 'conversation.status_changed'
  CONVERSATION_CONTACT_CHANGED = 'conversation.contact_changed'
  CONVERSATION_UNREAD_COUNT_CHANGED = 'conversation.unread_count_changed'
  ASSIGNEE_CHANGED = 'assignee.changed'
  TEAM_CHANGED = 'team.changed'
  CONVERSATION_TYPING_ON = 'conversation.typing_on'
  CONVERSATION_TYPING_OFF = 'conversation.typing_off'
  CONVERSATION_MENTIONED = 'conversation.mentioned'
  # conversation events (PR B7) — handlers implementados em B4 e G1
  CONVERSATION_USER_SETTING_CHANGED = 'conversation.user_setting_changed'
  CONVERSATION_PIN_ADDED = 'conversation.pin_added'
  CONVERSATION_PIN_REMOVED = 'conversation.pin_removed'

  # message events
  MESSAGE_CREATED = 'message.created'
  FIRST_REPLY_CREATED = 'first.reply.created'
  FIRST_REPLY_AFTER_ASSIGNMENT_CREATED = 'first.reply.after_assignment.created'
  REPLY_CREATED = 'reply.created'
  MESSAGE_UPDATED = 'message.updated'
  # message events (PR B7) — handlers implementados em B1
  MESSAGE_REACTION_ADDED = 'message.reaction_added'
  MESSAGE_REACTION_REMOVED = 'message.reaction_removed'

  # contact events
  CONTACT_CREATED = 'contact.created'
  CONTACT_UPDATED = 'contact.updated'
  CONTACT_MERGED = 'contact.merged'
  CONTACT_DELETED = 'contact.deleted'

  # contact events
  INBOX_CREATED = 'inbox.created'
  INBOX_UPDATED = 'inbox.updated'

  # notification events
  NOTIFICATION_CREATED = 'notification.created'
  NOTIFICATION_DELETED = 'notification.deleted'
  NOTIFICATION_UPDATED = 'notification.updated'

  # agent events
  AGENT_ADDED = 'agent.added'
  AGENT_REMOVED = 'agent.removed'

  # copilot events
  COPILOT_MESSAGE_CREATED = 'copilot.message.created'

  # kanban (funnel) events — contrato em task/kanban-tempo-real.md.
  # O nome com '.' vira método do listener com '_' (Events::Base#method_name).
  FUNNEL_ITEM_MOVED = 'funnel_item.moved'
  FUNNEL_ITEM_CREATED = 'funnel_item.created'
  FUNNEL_ITEM_DELETED = 'funnel_item.deleted'
  FUNNEL_ITEMS_BULK_MOVED = 'funnel_items.bulk_moved'
  FUNNEL_ITEMS_REORDERED = 'funnel_items.reordered'
  FUNNEL_STAGES_CHANGED = 'funnel_stages.changed'
end
