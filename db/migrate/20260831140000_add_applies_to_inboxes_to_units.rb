class AddAppliesToInboxesToUnits < ActiveRecord::Migration[7.1]
  # Interruptor por unidade, não feature flag: a bitmask de feature_flags está
  # esgotada (63 bits) e este efeito precisa nascer desligado de qualquer forma —
  # quem cadastrou unidade só para consulta não pode ter a caixa fechando sozinha.
  def change
    add_column :units, :applies_to_inboxes, :boolean, default: false, null: false
  end
end
