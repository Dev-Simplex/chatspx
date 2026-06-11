module Enterprise::ActionService
  def add_sla(sla_policy_id)
    return if sla_policy_id.blank?

    sla_policy = @account.sla_policies.find_by(id: sla_policy_id.first)
    return if sla_policy.nil?
    return if @conversation.sla_policy.present?

    Rails.logger.info "SLA:: Adding SLA #{sla_policy.id} to conversation: #{@conversation.id}"
    @conversation.update!(sla_policy_id: sla_policy.id)
  end

  # C4 do modelo IA-como-agente: atribui um agente de IA (Captain::Assistant) à conversa
  # via espelho AgentBot. Usado pela triagem (ex.: conversation_created -> recepcionista).
  # Não rouba conversa que já tem dono (humano ou IA) — triagem só pega órfãs.
  def assign_ai_agent(assistant_ids)
    return if assistant_ids.blank?
    return if @conversation.assignee_id.present? || @conversation.assignee_agent_bot_id.present?

    assistant = Captain::Assistant.where(account_id: @account.id).find_by(id: assistant_ids.first)
    return if assistant.nil?

    mirror = assistant.mirror_agent_bot
    return if mirror.nil?

    Rails.logger.info "Captain:: Assigning AI agent #{assistant.name} to conversation: #{@conversation.id}"
    @conversation.update!(assignee_agent_bot_id: mirror.id)
  end
end
