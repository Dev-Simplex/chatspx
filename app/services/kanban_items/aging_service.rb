# frozen_string_literal: true

# KANBAN-P2-02: calcula `aging_days` (numero de dias na stage atual)
# com base em `last_stage_change_at`. Pode receber escopo unitario ou
# em lote (default = todos os items abertos do account/kanban).
class KanbanItems::AgingService
  attr_reader :scope

  def initialize(scope: KanbanItem.all)
    @scope = scope
  end

  # Atualiza aging_days + aging_calculated_at em lote.
  # Usa update_all (1 query) com expressao SQL.
  def perform
    now = Time.current
    scope.where.not(last_stage_change_at: nil).update_all( # rubocop:disable Rails/SkipsModelValidations
      [
        'aging_days = EXTRACT(EPOCH FROM (? - last_stage_change_at))::int / 86400,
         aging_calculated_at = ?',
        now, now
      ]
    )
  end

  def self.call(scope: KanbanItem.all)
    new(scope: scope).perform
  end
end
