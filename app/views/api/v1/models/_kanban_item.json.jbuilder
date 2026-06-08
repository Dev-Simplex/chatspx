json.id resource.id
json.conversation_id resource.conversation_id
json.kanban_id resource.kanban_id
json.kanban_stage_id resource.kanban_stage_id
# Backward-compat: frontend ainda le funnel_id/funnel_stage_id; remover apos P0-08
json.funnel_id resource.kanban_id
json.funnel_stage_id resource.kanban_stage_id
json.moved_at resource.moved_at
json.last_stage_change_at resource.last_stage_change_at
json.aging_days resource.aging_days
json.won_reason resource.won_reason
json.loss_reason resource.loss_reason
json.note resource.note
json.metadata resource.metadata || {}
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
