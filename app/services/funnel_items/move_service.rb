# frozen_string_literal: true

class FunnelItems::MoveService
  attr_reader :conversation, :funnel, :funnel_stage, :moved_by

  def initialize(conversation:, funnel:, funnel_stage:, moved_by:)
    @conversation = conversation
    @funnel = funnel
    @funnel_stage = funnel_stage
    @moved_by = moved_by
  end

  def perform
    funnel_item = FunnelItem.find_or_initialize_by(
      conversation: conversation,
      funnel: funnel
    )

    funnel_item.assign_attributes(
      funnel_stage: funnel_stage,
      moved_by: moved_by,
      moved_at: Time.current
    )

    # Capture before persisting: true for a brand-new placement or a real move,
    # false for a no-op "move" to the same stage (so we don't broadcast noise).
    stage_changed = funnel_item.will_save_change_to_funnel_stage_id?

    # Nova colocação ou troca de coluna → topo da coluna de destino com position
    # única (fractional indexing), em vez do default 0 que colidiria.
    funnel_item.position = FunnelItem.top_position_for(funnel_stage.id, excluding_id: funnel_item.id) if stage_changed

    funnel_item.save!

    update_conversation_status

    if stage_changed
      broadcast_move(funnel_item)
      run_automations(funnel_item)
    end

    funnel_item
  end

  private

  # Fase 5: fire declarative automations for a card entering a stage. Best-effort
  # — the engine has its own per-rule rescue + reentrancy guard, but we wrap here
  # too so a move never breaks on automation trouble. Legacy open/resolved status
  # automation above is untouched.
  def run_automations(funnel_item)
    Kanban::AutomationEngineService.new(
      funnel: funnel,
      conversation: conversation,
      funnel_item: funnel_item,
      moved_by: moved_by
    ).run(event: 'item_entered_stage')
  rescue StandardError => e
    Rails.logger.warn("FunnelItems::MoveService automations failed: #{e.message}")
  end

  # Kanban tempo real: avisa os outros boards abertos para relocar (ou inserir)
  # este card. Best-effort — o rescue e o kill switch moram no Kanban::Realtime.
  def broadcast_move(funnel_item)
    Kanban::Realtime.dispatch(
      Events::Types::FUNNEL_ITEM_MOVED,
      funnel_item: funnel_item,
      moved_by: moved_by
    )
  end

  def update_conversation_status
    return if funnel_stage.automation_type.blank?
    return if conversation.blank?

    case funnel_stage.automation_type
    when 'resolved'
      resolve_conversation_from_automation! unless conversation.resolved?
    when 'open'
      conversation.update!(status: :open) unless conversation.open?
    end
  end

  def resolve_conversation_from_automation!
    conversation.skip_team_required_for_resolution_validation = true
    conversation.update!(status: :resolved)
  ensure
    conversation.skip_team_required_for_resolution_validation = false
  end
end
