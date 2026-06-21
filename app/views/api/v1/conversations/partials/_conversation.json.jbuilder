# TODO: Move this into models jbuilder
# Currently the file there is used only for search endpoint.
# Everywhere else we use conversation builder in partials folder

json.meta do # rubocop:disable Metrics/BlockLength
  if conversation.contact.present?
    contact = conversation.contact
    json.sender do
      json.additional_attributes contact.additional_attributes
      json.availability_status contact.availability_status
      json.email contact.email
      json.id contact.id
      json.name contact.name
      json.phone_number contact.phone_number
      json.blocked contact.blocked
      json.identifier contact.identifier
      json.thumbnail contact.avatar_url
      json.custom_attributes contact.custom_attributes
      json.last_activity_at contact.last_activity_at.to_i if contact[:last_activity_at].present?
      json.created_at contact.created_at.to_i if contact[:created_at].present?
    end
  else
    json.sender do
      json.additional_attributes({})
      json.availability_status(nil)
      json.email(nil)
      json.id(conversation.contact_id)
      json.name('Deleted Contact')
      json.phone_number(nil)
      json.blocked(false)
      json.identifier(nil)
      json.thumbnail('')
      json.custom_attributes({})
    end
  end
  json.channel conversation.inbox.try(:channel_type)
  if conversation.assignee.present?
    assignee = conversation.assignee
    json.assignee do
      json.id assignee.id
      json.account_id Current.account&.id
      json.availability_status assignee.availability_status
      json.auto_offline assignee.auto_offline
      json.confirmed assignee.confirmed?
      json.email assignee.email
      json.available_name assignee.available_name
      json.custom_attributes assignee.custom_attributes if assignee.custom_attributes.present?
      json.name assignee.name
      json.role assignee.role
      json.thumbnail assignee.avatar_url
      json.team_ids assignee.teams.select { |t| t.account_id == Current.account&.id }.map(&:id)
      json.custom_role_id assignee.current_account_user&.custom_role_id if ChatwootApp.enterprise?
    end
  elsif conversation.assignee_agent_bot&.captain?
    # Assignee-IA (espelho captain) — mesmo shape do push_event_data + discriminador type (DC-3).
    # Bot webhook atribuído via coluna NÃO entra (comportamento atual preservado).
    bot = conversation.assignee_agent_bot
    json.assignee do
      json.id bot.id
      json.account_id Current.account&.id
      json.name bot.name
      json.available_name bot.name
      json.avatar_url bot.avatar_url
      json.thumbnail bot.avatar_url
      json.type 'agent_bot'
      json.bot_type bot.bot_type
      # Discriminador único que o front usa nas abas IA / Não Atribuídas
      # (casa com o is_captain do push_event_data via websocket). Aqui é sempre
      # true pois só espelhos captain entram neste branch.
      json.is_captain bot.captain?
      json.captain_assistant_id bot.captain_assistant_id
    end
  elsif conversation.assignee_id.present?
    json.assignee do
      json.id(conversation.assignee_id)
      json.name('Agente Removido')
      json.available_name('Agente Removido')
      json.avatar_url('')
      json.thumbnail('')
      json.availability_status(nil)
      json.role(nil)
    end
  end
  if conversation.team.present?
    team = conversation.team
    json.team do
      json.id team.id
      json.name team.name
      json.description team.description
      json.allow_auto_assign team.allow_auto_assign
      json.account_id team.account_id
      json.is_member @current_user_team_ids&.include?(team.id) || Current.user&.teams&.exists?(id: team.id)
    end
  end
  json.hmac_verified conversation.contact_inbox&.hmac_verified
end

json.id conversation.display_id
preloaded = @list_preloaded
if preloaded
  last_message = preloaded.last_messages[conversation.id]
  if last_message.blank?
    json.messages []
  else
    json.messages [last_message.try(:push_event_data)]
  end
else
  fallback_rid = AgentMessageIsolation.restriction_id_for_inbox(conversation.inbox, Current.user, conversation.account_id)
  fallback_scope = conversation.messages.where(account_id: conversation.account_id)
                               .includes([{ attachments: [{ file_attachment: [:blob] }] }])
  fallback_last = AgentMessageIsolation.filter_messages(fallback_scope, fallback_rid).last
  json.messages fallback_last.blank? ? [] : [fallback_last.try(:push_event_data)]
end

json.account_id conversation.account_id
json.uuid conversation.uuid
json.additional_attributes conversation.additional_attributes
json.agent_last_seen_at conversation.agent_last_seen_at.to_i
json.assignee_last_seen_at conversation.assignee_last_seen_at.to_i
json.can_reply conversation.can_reply?
json.contact_last_seen_at conversation.contact_last_seen_at.to_i
json.custom_attributes conversation.custom_attributes
json.inbox_id conversation.inbox_id
json.labels conversation.cached_label_list_array
json.muted conversation.muted?
json.snoozed_until conversation.snoozed_until
json.status conversation.status
json.created_at conversation.created_at.to_i
json.updated_at conversation.updated_at.to_f
json.timestamp conversation.last_activity_at.to_i
json.first_reply_created_at conversation.first_reply_created_at.to_i
json.unread_count preloaded ? preloaded.unread_counts[conversation.id].to_i : conversation.unread_incoming_messages.count
last_non_activity_msg = if preloaded
                          preloaded.last_non_activity_messages[conversation.id]
                        else
                          na_rid = AgentMessageIsolation.restriction_id_for_inbox(conversation.inbox, Current.user, conversation.account_id)
                          na_scope = conversation.messages.where(account_id: conversation.account_id).non_activity_messages
                          AgentMessageIsolation.filter_messages(na_scope, na_rid).first
                        end
json.last_non_activity_message last_non_activity_msg.try(:push_event_data)
json.last_activity_at conversation.last_activity_at.to_i
json.priority conversation.priority
json.waiting_since conversation.waiting_since.to_i.to_i
json.sla_policy_id conversation.sla_policy_id
json.partial! 'enterprise/api/v1/conversations/partials/conversation', conversation: conversation if ChatwootApp.enterprise?
