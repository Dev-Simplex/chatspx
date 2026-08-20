module Enterprise::Inbox
  def member_ids_with_assignment_capacity
    return super unless enable_auto_assignment?

    max_assignment_limit = auto_assignment_config['max_assignment_limit']
    overloaded_agent_ids = max_assignment_limit.present? ? get_agent_ids_over_assignment_limit(max_assignment_limit) : []
    super - overloaded_agent_ids
  end

  def active_bot?
    super || captain_active?
  end

  # A9.1: re-keyado pra ELEGIBILIDADE (has_many do A5). "Inbox tem IA elegível + cota".
  # Mantém active_bot? = super || captain_active? para os 4 consumidores (pending na
  # criação/reopen + métricas "inbox tem bot"). A SUPRESSÃO real (gate por atribuição)
  # vive no hook_execution_service, não aqui.
  def captain_active?
    captain_assistants.exists? && more_responses?
  end

  private

  def more_responses?
    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def get_agent_ids_over_assignment_limit(limit)
    conversations
      .open
      .where(account_id: account_id)
      .select(:assignee_id)
      .group(:assignee_id)
      .having("count(*) >= #{limit.to_i}")
      .filter_map(&:assignee_id)
  end

  def ensure_valid_max_assignment_limit
    return if auto_assignment_config['max_assignment_limit'].blank?
    return if auto_assignment_config['max_assignment_limit'].to_i.positive?

    errors.add(:auto_assignment_config, 'max_assignment_limit must be greater than 0')
  end
end
