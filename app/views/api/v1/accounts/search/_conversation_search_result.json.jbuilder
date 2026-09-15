json.partial! 'api/v1/conversations/partials/conversation',
              formats: [:json],
              conversation: conversation

# `messages` tem escopo por time (Conversation#messages): o agente que nao enxerga nenhuma
# mensagem desta conversa recebe nil aqui, e o parcial faz `message.id` — 500 na busca inteira
# por causa de uma linha do resultado. Vale tambem para conversa sem mensagem alguma, que a
# busca devolve porque casa pelo CONTATO. Guardado como contact, inbox e agent logo abaixo.
primeira_mensagem = conversation.messages.first

json.message do
  json.partial! 'message', formats: [:json], message: primeira_mensagem if primeira_mensagem.present?
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
