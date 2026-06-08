# frozen_string_literal: true

class Kanban::KanbanItemsBackfillService
  DEFAULT_MAX_ITEMS = 1000

  def initialize(account:, kanban:, moved_by_id: nil, max_items: DEFAULT_MAX_ITEMS)
    @account = account
    @kanban = kanban
    @moved_by_id = moved_by_id
    @max_items = max_items
  end

  def perform # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    return if account.blank? || kanban.blank?

    stages = kanban.kanban_stages.ordered.to_a
    return if stages.empty?

    default_stage = stages.first
    stage_by_automation = stages.index_by(&:automation_type)
    missing_conversations = conversations_missing_kanban_item
    return if missing_conversations.empty?

    now = Time.current
    rows = missing_conversations.filter_map do |conversation|
      stage = stage_for_conversation(conversation, stage_by_automation, default_stage)
      next unless stage

      {
        kanban_id: kanban.id,
        conversation_id: conversation.id,
        kanban_stage_id: stage.id,
        moved_by_id: moved_by_id,
        last_stage_change_at: now,
        created_at: now,
        updated_at: now
      }
    end

    return if rows.empty?

    KanbanItem.insert_all(rows, unique_by: :idx_kanban_items_unique) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  attr_reader :account, :kanban, :moved_by_id

  def conversations_missing_kanban_item
    relation = account.conversations.where(status: [:open, :resolved])
    relation = relation.where(team_id: kanban.team_id) if kanban.team_id.present?

    inbox_ids = normalize_inbox_ids(kanban.inbox_ids)
    relation = relation.where(inbox_id: inbox_ids) if inbox_ids.any?

    existing_conversation_ids = KanbanItem.where(kanban_id: kanban.id).select(:conversation_id)
    relation.where.not(id: existing_conversation_ids).limit(max_items)
  end

  def stage_for_conversation(conversation, stage_by_automation, default_stage)
    case conversation.status
    when 'open'
      stage_by_automation['open'] || default_stage
    when 'resolved'
      stage_by_automation['resolved'] || default_stage
    else
      default_stage
    end
  end

  def normalize_inbox_ids(inbox_ids)
    return [] unless inbox_ids.is_a?(Array)

    inbox_ids.filter_map do |value|
      Integer(value)
    rescue StandardError
      nil
    end.uniq
  end

  def max_items
    requested = Integer(@max_items)
    requested.positive? ? requested : DEFAULT_MAX_ITEMS
  rescue ArgumentError, TypeError
    DEFAULT_MAX_ITEMS
  end
end
