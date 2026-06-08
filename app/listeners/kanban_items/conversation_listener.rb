# frozen_string_literal: true

# Listener Wisper que reage a eventos de Conversation e gerencia KanbanItems.
# Substitui callbacks `add_to_appropriate_funnel`, `move_to_team_funnel`,
# `move_to_automated_stage` que viviam em Conversation (acoplamento forte).
#
# Vantagem: dueto Conversation/Kanban desacopla. Pra desligar Kanban inteiro,
# basta `KanbanItems::ConversationListener.disabled = true` sem mexer em Conversation.
class KanbanItems::ConversationListener
  class << self
    attr_accessor :disabled
  end

  def on_conversation_created(conversation)
    return if self.class.disabled

    ensure_kanban_items_for(conversation)
  rescue StandardError => e
    Rails.logger.error("[KanbanListener] conversation_created falhou: #{e.message}")
    raise unless Rails.env.production?
  end

  def on_conversation_status_changed(conversation)
    return if self.class.disabled

    move_to_automated_stage(conversation)
  rescue StandardError => e
    Rails.logger.error("[KanbanListener] conversation_status_changed falhou: #{e.message}")
    raise unless Rails.env.production?
  end

  def on_conversation_team_changed(conversation)
    return if self.class.disabled

    move_to_team_kanban(conversation)
  rescue StandardError => e
    Rails.logger.error("[KanbanListener] conversation_team_changed falhou: #{e.message}")
    raise unless Rails.env.production?
  end

  private

  def ensure_kanban_items_for(conversation)
    kanbans = Kanban::KanbanLookupService.new(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      team_id: conversation.team_id
    ).perform
    return if kanbans.blank?

    kanbans.each { |kanban| ensure_kanban_item_for(kanban, conversation) }
  end

  def ensure_kanban_item_for(kanban, conversation)
    stage = stage_for_new_item(kanban)
    return unless stage

    item = KanbanItem.find_or_create_by(kanban_id: kanban.id, conversation_id: conversation.id) do |i|
      i.kanban_stage_id = stage.id
    end
    enqueue_captain_triage(item) if item.persisted? && triage_enabled_for?(kanban)
  end

  def stage_for_new_item(kanban)
    kanban.kanban_stages.find_by(automation_type: 'open') ||
      kanban.kanban_stages.find_by(automation_type: 'resolved') ||
      kanban.kanban_stages.ordered.first
  end

  def triage_enabled_for?(kanban)
    settings = kanban.settings || {}
    explicit = settings['ai_triage_enabled']
    return ActiveModel::Type::Boolean.new.cast(explicit) unless explicit.nil?

    ENV['ENABLE_KANBAN_AI_TRIAGE'].present?
  end

  def enqueue_captain_triage(item)
    KanbanCaptain::TriageJob.set(wait: 10.seconds).perform_later(item.id)
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').warn("enqueue failed: #{e.message}")
  end

  def move_to_automated_stage(conversation)
    Kanban::MoveConversationToAutomatedStageService.new(
      conversation: conversation,
      status: conversation.status
    ).perform
  end

  def move_to_team_kanban(conversation)
    Kanban::MoveConversationToTeamKanbanService.new(
      conversation: conversation,
      team: conversation.team_id.present? ? conversation.team : nil
    ).perform
  end
end
