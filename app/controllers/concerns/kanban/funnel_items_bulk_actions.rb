# frozen_string_literal: true

# Kanban v2 — bulk operations over funnel cards, extracted from
# FunnelItemsController to keep it focused. Relies on the host controller's
# `funnel` helper and the standard Current/authorization wiring.
module Kanban::FunnelItemsBulkActions
  extend ActiveSupport::Concern

  # Move many conversations to a single stage (Trello-style multi-drag / list bulk).
  def bulk_move
    stage_id = params[:stage_id]
    return render json: { error: 'stage_id is required' }, status: :unprocessable_entity if stage_id.blank?

    stage = funnel.funnel_stages.find(stage_id)
    Current.account.conversations.where(id: params[:conversation_ids] || []).find_each do |conversation|
      FunnelItems::MoveService.new(
        conversation: conversation,
        funnel: funnel,
        funnel_stage: stage,
        moved_by: Current.user
      ).perform
    end

    head :ok
  end

  # Bulk reassign / tag / archive over selected cards (Fase 3).
  def bulk_update
    conversations = Current.account.conversations.where(id: params[:conversation_ids] || [])
    result = FunnelItems::BulkUpdateService.new(
      account: Current.account,
      conversations: conversations,
      operation: params[:operation].to_s,
      performed_by: Current.user,
      params: { assignee_id: params[:assignee_id], labels: params[:labels] }
    ).perform

    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    render json: result
  end

  # Reordenação manual de cartões dentro de uma coluna (Kanban DB restructure / P1).
  # Recebe a lista ordenada de ids da stage e persiste `position` (1-based), para
  # que a ordem sobreviva a reload. Espelha o padrão de Funnels#reorder_stages.
  def reorder
    FunnelItems::ReorderService.new(
      funnel: funnel,
      funnel_stage_id: params[:funnel_stage_id],
      item_ids: params[:item_ids]
    ).perform
    head :ok
  rescue StandardError => e
    Rails.logger.error "FunnelItemsController#reorder: #{e.class} - #{e.message}"
    render json: { error: 'Error reordering items' }, status: :internal_server_error
  end
end
