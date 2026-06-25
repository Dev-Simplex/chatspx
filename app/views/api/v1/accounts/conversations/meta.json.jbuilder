json.meta do
  json.mine_count @conversations_count[:mine_count]
  json.assigned_count @conversations_count[:assigned_count]
  json.unassigned_count @conversations_count[:unassigned_count]
  json.ai_count @conversations_count[:ai_count]
  json.awaiting_count @conversations_count[:awaiting_count]
  json.all_count @conversations_count[:all_count]
  json.unattended_assigned_to_me_count @conversations_count[:unattended_assigned_to_me_count]
  json.unattended_unassigned_count @conversations_count[:unattended_unassigned_count]
  json.unattended_all_count @conversations_count[:unattended_all_count]
end
