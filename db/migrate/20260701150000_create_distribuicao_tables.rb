# Motor de Distribuição (F1) — 3 tabelas additivas. Ver docs/MOTOR-DISTRIBUICAO.md §10.2.
# Additiva e inerte: sem política criada, o Motor é no-op. Aplicar com alvo específico
# (db:migrate:up VERSION=20260701150000) para não disparar migrations destrutivas pendentes.
class CreateDistribuicaoTables < ActiveRecord::Migration[7.1]
  def change
    create_table :distribuicao_policies do |t|
      t.bigint  :account_id, null: false
      t.bigint  :team_id,    null: false
      t.boolean :ativo,               null: false, default: true
      t.string  :modo,                null: false, default: 'rodizio' # rodizio | online | off
      t.boolean :so_online,           null: false, default: false
      t.boolean :continuidade_ativa,  null: false, default: true
      t.integer :continuidade_dias,   null: false, default: 30
      t.jsonb   :pool, null: false, default: [] # [{user_id, ativo, cap}]
      t.timestamps
    end
    add_index :distribuicao_policies, %i[account_id team_id], unique: true

    create_table :distribuicao_states do |t|
      t.bigint :team_id, null: false
      t.bigint :last_user_id
      t.timestamps
    end
    add_index :distribuicao_states, :team_id, unique: true

    create_table :distribuicao_logs do |t|
      t.bigint   :account_id,      null: false
      t.bigint   :conversation_id, null: false
      t.bigint   :chosen_user_id
      t.string   :motivo, null: false # continuidade | rodizio | sem_pool
      t.jsonb    :candidatos, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :distribuicao_logs, :conversation_id
  end
end
