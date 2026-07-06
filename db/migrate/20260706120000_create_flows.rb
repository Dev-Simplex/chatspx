# frozen_string_literal: true

# Flow — motor único que unifica Macro (disparo manual) e AutomationRule (disparo por
# evento) sobre o ActionService compartilhado. `definition` (jsonb: nodes+edges) é a
# fonte da verdade; o canvas apenas a renderiza. Espelha o schema de `automation_rules`
# (event_name/conditions passam a viver em `trigger_config`) e `macros` (visibility/
# created_by). As colunas `reentry_policy`/`goal_conditions` nascem inertes — habilitam
# enrollment/compliance na Fase 2. Ver plano/automacoes-plano-mestre.md §2.1.
class CreateFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :flows do |t|
      t.references :account, null: false, index: true
      t.string   :name, null: false
      t.text     :description
      t.integer  :trigger_type, null: false, default: 0    # manual/conversation_event/schedule/keyword/external_webhook
      t.jsonb    :trigger_config, null: false, default: {}  # polimórfico por trigger_type (event_name, conditions, cron, keywords…)
      t.jsonb    :definition, null: false, default: { 'nodes' => [], 'edges' => [] }
      t.boolean  :active, null: false, default: true
      t.integer  :version, null: false, default: 1          # bump a cada publish; o flow_run fixa a versão (F2)
      t.integer  :visibility, null: false, default: 1       # personal:0 / global:1 (espelha macros.visibility)
      t.integer  :reentry_policy, null: false, default: 0   # once:0 / re_enroll:1 / re_enroll_after:2 — inerte até F2
      t.jsonb    :goal_conditions, null: false, default: {} # meta de saída — inerte até F2
      t.bigint   :created_by_id
      t.bigint   :updated_by_id
      t.timestamps
    end
    add_index :flows, [:account_id, :trigger_type, :active]
  end
end
