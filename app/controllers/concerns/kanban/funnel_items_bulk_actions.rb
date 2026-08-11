# frozen_string_literal: true

# Kanban v2 — bulk operations over funnel cards, extracted from
# FunnelItemsController to keep it focused. Relies on the host controller's
# `funnel` helper and the standard Current/authorization wiring.
module Kanban::FunnelItemsBulkActions
  extend ActiveSupport::Concern

  # Move many conversations to a single stage (Trello-style multi-drag / list bulk).
  #
  # Tempo real (Fase 2.3): o broadcast individual do MoveService é SUPRIMIDO e no
  # fim sai UM evento agregado. Antes, mover 50 cards enfileirava 50
  # ActionCableBroadcastJob na fila `:critical`, cada um publicando para todos os
  # usuários do público do funil — 1.500 publicações numa conta de 30 agentes.
  def bulk_move
    stage_id = params[:stage_id]
    return render json: { error: 'stage_id is required' }, status: :unprocessable_entity if stage_id.blank?

    stage = funnel.funnel_stages.find(stage_id)
    moved_ids = []
    Current.account.conversations.where(id: params[:conversation_ids] || []).find_each do |conversation|
      item = FunnelItems::MoveService.new(
        conversation: conversation,
        funnel: funnel,
        funnel_stage: stage,
        moved_by: Current.user,
        broadcast: false
      ).perform
      moved_ids << item.id
    end

    broadcast_bulk_move(moved_ids)
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

  private

  # Só ids: o listener recarrega com `includes` para montar os payloads sem N+1
  # (e aplica o teto acima do qual o evento vira ordem de refetch).
  def broadcast_bulk_move(item_ids)
    return if item_ids.blank?

    Kanban::Realtime.dispatch(Events::Types::FUNNEL_ITEMS_BULK_MOVED, funnel: funnel, item_ids: item_ids)
  end
end
