# Painel "Execuções"/Logs — os step-logs do flow, mais recentes primeiro, paginados. Cada linha é
# um FlowStepLog (um nó executado no disparo real). `status` sai como string do enum
# (success/failed/skipped) pra a UI mapear cor + rótulo traduzido. `created_at` em epoch (segundos).
json.payload do
  json.array! @logs do |log|
    json.id log.id
    json.status log.status
    json.node_id log.node_id
    json.action_name log.action_name
    json.branch_key log.branch_key
    json.error_code log.error_code
    json.error_message log.error_message
    json.duration_ms log.duration_ms
    json.conversation_id log.conversation_id
    json.created_at log.created_at.to_i
  end
end
json.meta do
  json.current_page @logs.current_page
  json.total_pages @logs.total_pages
  json.total_count @logs.total_count
end
