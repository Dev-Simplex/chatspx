# frozen_string_literal: true

class RemoveFunnelItemsInResolvedStage < ActiveRecord::Migration[7.0]
  def up
    resolved_stage_ids = FunnelStage.where(automation_type: 'resolved').pluck(:id)
    return if resolved_stage_ids.empty?

    deleted = FunnelItem.where(funnel_stage_id: resolved_stage_ids).delete_all
    say "Removidos #{deleted} funnel_items da etapa Resolvido (limpeza pós backfill)."
  end

  def down
    # Não restaura os itens removidos; o backfill antigo não roda mais para resolved.
    say "Nenhuma reversão automática. Itens removidos não são recriados."
  end
end
