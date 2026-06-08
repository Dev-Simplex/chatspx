# frozen_string_literal: true

# KANBAN-P3-05: dispatch de automations.
# Roda assíncrono via KanbanAutomationJob.
#
# Triggers:
#  - item_entered_stage (stage_id alvo: nova stage)
#  - item_left_stage    (stage_id alvo: stage anterior)
#  - item_aging_threshold (aging_days >= conditions.days)
#
# Cada action é resolvida via mapeamento simples:
#  - send_template      → KanbanItems::SendTemplateOnMoveService
#  - assign             → conversation.update(assignee_id:)
#  - add_label          → conversation.add_labels([title])
#  - move               → KanbanItems::MoveService
#  - create_task        → cria Captain::Task se disponível, senão nota interna
class KanbanAutomations::DispatcherService
  attr_reader :trigger, :item, :previous_stage_id

  def initialize(trigger:, item:, previous_stage_id: nil)
    @trigger = trigger
    @item = item
    @previous_stage_id = previous_stage_id
  end

  def perform
    return if item.blank?

    automations.each do |automation|
      next unless conditions_match?(automation)

      execute(automation)
    rescue StandardError => e
      Rails.logger.tagged('kanban-automations').error(
        "automation=#{automation.id} item=#{item.id} #{e.class}: #{e.message}"
      )
    end
  end

  def self.fire(trigger:, item:, previous_stage_id: nil)
    KanbanAutomationJob.perform_later(trigger.to_s, item.id, previous_stage_id)
  end

  private

  def automations
    scope = item.kanban.kanban_automations.enabled.by_trigger(trigger)
    target_stage_id = case trigger
                      when 'item_left_stage' then previous_stage_id
                      else item.kanban_stage_id
                      end
    scope.for_stage(target_stage_id)
  end

  def conditions_match?(automation)
    return true if automation.trigger != 'item_aging_threshold'

    days = automation.conditions.is_a?(Hash) ? automation.conditions['days'].to_i : 0
    days.zero? || item.aging_days.to_i >= days
  end

  def execute(automation)
    Array(automation.actions).each do |raw|
      action = raw.is_a?(Hash) ? raw.with_indifferent_access : { type: raw }.with_indifferent_access
      type = action[:type] || action['type']
      send("execute_#{type}", action) if KanbanAutomation::ACTION_TYPES.include?(type)
    end
  end

  def execute_send_template(action)
    return if action[:template_id].blank? && action[:template_slug].blank?

    KanbanItems::SendTemplateOnMoveService.call(
      item: item,
      user: nil,
      template_id: action[:template_id] || action[:template_slug],
      variables_override: (action[:variables] || {}).to_h
    )
  end

  def execute_assign(action)
    agent_id = action[:agent_id] || action[:user_id]
    return if agent_id.blank?

    item.conversation.update(assignee_id: agent_id)
  end

  def execute_add_label(action)
    label_id = action[:label_id]
    title = action[:title]
    if label_id.present?
      label = item.kanban.account.labels.find_by(id: label_id)
      title ||= label&.title
    end
    return if title.blank?

    if item.conversation.respond_to?(:add_labels)
      item.conversation.add_labels([title])
    else
      item.conversation.update(cached_label_list: title)
    end
  end

  def execute_move(action)
    stage_id = action[:stage_id] || action[:kanban_stage_id]
    return if stage_id.blank? || item.kanban_stage_id.to_i == stage_id.to_i

    stage = item.kanban.kanban_stages.find_by(id: stage_id)
    return if stage.blank?

    KanbanItems::MoveService.new(
      conversation: item.conversation,
      kanban: item.kanban,
      kanban_stage: stage,
      moved_by: nil
    ).perform
  end

  def execute_create_task(action)
    title = action[:title].presence || "Acompanhar #{item.conversation&.contact&.name}"
    if defined?(Captain::Task)
      Captain::Task.create(account_id: item.kanban.account_id, title: title)
    else
      params = ActionController::Parameters.new(
        content: "📋 Tarefa: #{title}",
        message_type: 'outgoing',
        private: true,
        content_attributes: { sent_from: 'kanban_automation_task' }
      )
      Messages::MessageBuilder.new(nil, item.conversation, params).perform
    end
  end
end
