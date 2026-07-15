# frozen_string_literal: true

# Persiste a ordem manual dos cartões dentro de uma coluna do Kanban (P1 do plano
# task/kanban-db-restructure.md). Recebe a lista ordenada de ids da stage e grava
# `position` 1-based (mesma base do backfill da migration), de modo que a ordem
# sobreviva a reload. Espelha Funnels::ReorderStagesService.
#
# Usa update_all (pula validações/callbacks) de propósito: reordenar NÃO deve
# disparar o before_save :set_moved_at (que só muda em troca de stage) nem tocar
# updated_at semânticamente relevante para "tempo em stage".
class FunnelItems::ReorderService
  attr_reader :funnel, :funnel_stage_id, :item_ids

  def initialize(funnel:, funnel_stage_id:, item_ids:)
    @funnel = funnel
    @funnel_stage_id = funnel_stage_id.to_s.to_i
    @item_ids = Array(item_ids).map { |id| id.to_s.to_i }.reject(&:zero?).uniq
  end

  def perform
    return if item_ids.blank? || funnel_stage_id.zero?

    scope = funnel.funnel_items.where(funnel_stage_id: funnel_stage_id)
    # Só reordena ids que realmente pertencem a esta funnel+stage (ignora ruído).
    valid_ids = scope.where(id: item_ids).pluck(:id)
    ordered_ids = item_ids.select { |id| valid_ids.include?(id) }
    return if ordered_ids.blank?

    ActiveRecord::Base.transaction do
      ordered_ids.each_with_index do |item_id, index|
        scope.where(id: item_id).update_all(position: index + 1) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
