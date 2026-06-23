json.id resource.id
json.conversation_id resource.conversation_id
json.funnel_id resource.funnel_id
json.funnel_stage_id resource.funnel_stage_id
json.moved_at resource.moved_at
json.moved_by_id resource.moved_by_id
json.created_at resource.created_at
json.updated_at resource.updated_at

if resource.conversation.present?
  json.conversation do
    json.id resource.conversation.id
    json.display_id resource.conversation.display_id
    json.status resource.conversation.status
    json.contact_id resource.conversation.contact_id
    json.inbox_id resource.conversation.inbox_id
    json.account_id resource.conversation.account_id
    json.assignee_id resource.conversation.assignee_id
    json.last_activity_at resource.conversation.last_activity_at
    label_titles = resource.conversation.cached_label_list_array
    if label_titles.present?
      labels_lookup = @labels_by_title || {}
      json.labels label_titles.map { |title|
        label = labels_lookup[title.to_s.downcase]
        { title: title, color: label&.color || '#94a3b8' }
      }
    end
    if resource.conversation.contact.present?
      json.contact do
        json.id resource.conversation.contact.id
        json.name resource.conversation.contact.name
        json.phone_number resource.conversation.contact.phone_number
        json.thumbnail resource.conversation.contact.avatar_url
      end
    end
    last_message = @last_messages_by_conversation_id&.[](resource.conversation_id)
    if last_message.present?
      json.last_message do
        json.content last_message.content
        json.processed_message_content last_message.processed_message_content
        json.created_at last_message.created_at
      end
    end
  end
end
