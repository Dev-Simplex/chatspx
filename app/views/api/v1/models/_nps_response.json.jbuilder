json.id resource.id
json.account_id resource.account_id
json.conversation_id resource.conversation_id
json.contact_id resource.contact_id
json.inbox_id resource.inbox_id
json.assigned_agent_id resource.assigned_agent_id
json.status resource.status
json.score resource.score
json.comment resource.comment
json.sent_at resource.sent_at&.to_i
json.answered_at resource.answered_at&.to_i
json.dismiss_reason resource.dismiss_reason
json.blocked_by_label resource.blocked_by_label
json.blocked_scope resource.blocked_scope
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i

if resource.assigned_agent.present?
  json.assigned_agent do
    json.id resource.assigned_agent.id
    json.name resource.assigned_agent.name
    json.email resource.assigned_agent.email
  end
end

if resource.contact.present?
  json.contact do
    json.id resource.contact.id
    json.name resource.contact.name
    json.email resource.contact.email
  end
end

if resource.conversation.present?
  json.conversation do
    json.id resource.conversation.id
    json.display_id resource.conversation.display_id
  end
end

if resource.inbox.present?
  json.inbox do
    json.id resource.inbox.id
    json.name resource.inbox.name
  end
end

json.classification resource.classification
