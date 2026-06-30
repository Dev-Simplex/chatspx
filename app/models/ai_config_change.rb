# Trilha de auditoria + dado de rollback de cada change-set de comportamento de IA
# aplicado nesta VM (ver Spx::AiConfig::ChangeSetApplier). snapshot_before guarda o
# estado anterior por operacao; result guarda ids criados — juntos permitem reverter.
class AiConfigChange < ApplicationRecord
  enum status: { applied: 0, reverted: 1, failed: 2 }

  validates :change_set_id, presence: true, uniqueness: true
  validates :account_id, presence: true
end
