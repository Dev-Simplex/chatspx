json.partial! 'api/v1/conversations/partials/conversation',
              formats: [:json],
              conversation: conversation

json.message do
  json.partial! 'message', formats: [:json], message: conversation.messages.try(:first)
end
json.contact do
  json.partial! 'contact', formats: [:json], contact: conversation.contact if conversation.try(:contact).present?
end
json.inbox do
  json.partial! 'inbox', formats: [:json], inbox: conversation.inbox if conversation.try(:inbox).present?
end
json.agent do
  json.partial! 'agent', formats: [:json], agent: conversation.assignee if conversation.try(:assignee).present?
end
