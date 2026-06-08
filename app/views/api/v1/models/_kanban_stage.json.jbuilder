json.id resource.id
json.name resource.name
json.kanban_id resource.kanban_id
# Backward-compat: frontend ainda le funnel_id; remover apos P0-08
json.funnel_id resource.kanban_id
json.position resource.position
json.color resource.color
json.automation_type resource.automation_type
# Phase 3 fields
json.probability resource.probability
json.wip_limit resource.wip_limit
json.default_message_template_id resource.default_message_template_id
json.rot_after_days resource.rot_after_days
json.won_loss_type resource.won_loss_type
json.settings(resource.settings || {})
json.created_at resource.created_at
json.updated_at resource.updated_at
