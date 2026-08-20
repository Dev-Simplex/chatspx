# ⚠️ MANTENHA EM SINCRONIA com `FunnelItem#push_event_data` (app/models/funnel_item.rb).
# Este partial é o card vindo do GET; o push_event_data é o MESMO card vindo do
# websocket. Campo que só existe aqui vira card "meio desenhado" quando ele chega
# pelo socket. Única diferença deliberada: `last_message` não vai no broadcast
# (query extra no caminho síncrono do arraste). Travado por
# spec/models/funnel_item_push_event_data_spec.rb.
json.id resource.id
json.conversation_id resource.conversation_id
json.funnel_id resource.funnel_id
json.funnel_stage_id resource.funnel_stage_id
json.moved_at resource.moved_at
json.moved_by_id resource.moved_by_id
json.position resource.position
json.created_at resource.created_at
json.updated_at resource.updated_at

# Cartão de tarefa/lembrete (avulso, sem conversa): título/descrição/responsável.
json.is_task resource.task?
json.title resource.title
json.description resource.description
json.assignee_id resource.assignee_id
if resource.assignee.present?
  json.assignee do
    json.id resource.assignee.id
    json.name resource.assignee.name
    json.thumbnail resource.assignee.avatar_url
  end
end

if resource.conversation.present?
  json.conversation do
    json.id resource.conversation.id
    json.display_id resource.conversation.display_id
    json.status resource.conversation.status
    json.priority resource.conversation.priority
    json.contact_id resource.conversation.contact_id
    json.inbox_id resource.conversation.inbox_id
    json.account_id resource.conversation.account_id
    json.assignee_id resource.conversation.assignee_id
    json.last_activity_at resource.conversation.last_activity_at
    json.waiting_since resource.conversation.waiting_since
    # Kanban v2 (Fase 2): only this funnel's namespaced custom field values.
    funnel_attrs = (resource.conversation.custom_attributes || {}).select do |key, _|
      key.to_s.start_with?("funnel_#{resource.funnel_id}_")
    end
    json.custom_attributes funnel_attrs
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
