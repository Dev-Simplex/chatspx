# frozen_string_literal: true

# P0 do plano task/kanban-db-restructure.md — remove o schema drift `kanban_*`.
#
# Contexto: as 6 tabelas kanban_* entraram no db/schema.rb via merge (commit 2bee0f724)
# SEM migration correspondente no tree. O banco real (db:migrate) nunca as criou; apenas
# ambientes carregados via db:schema:load (test/dev novos) nascem com elas. Não há model,
# controller, service ou qualquer referência em app/ ou lib/ — são tabelas fantasma.
# A implementação viva do Kanban usa a família funnel_*.
#
# up:   idempotente (if_exists) — no prod não faz nada; em test/dev limpa o lixo.
# down: reversível — recria as defs exatas que estavam no schema.rb, caso alguém
#       queira ressuscitar o desenho (que, ironicamente, é mais robusto que o vivo).
class DropOrphanKanbanTables < ActiveRecord::Migration[7.1]
  # Ordem topológica: dependentes primeiro. kanbans referencia kanban_templates
  # (template_id), portanto kanban_templates é dropado por ÚLTIMO.
  DROP_ORDER = %i[
    kanban_automations
    kanban_items
    kanban_views
    kanban_stages
    kanbans
    kanban_templates
  ].freeze

  def up
    DROP_ORDER.each { |table| drop_table(table, if_exists: true) }
  end

  def down # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :kanban_templates do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :description, limit: 500
      t.string :vertical
      t.string :icon, limit: 32
      t.string :color, limit: 16
      t.string :locale, default: 'pt-BR', null: false
      t.integer :version, default: 1, null: false
      t.jsonb :stages_config, default: [], null: false
      t.jsonb :sample_cards, default: [], null: false
      t.jsonb :automations_config, default: [], null: false
      t.boolean :is_official, default: true, null: false
      t.bigint :account_id
      t.timestamps
      t.index [:account_id], name: 'index_kanban_templates_on_account_id'
      t.index [:locale], name: 'index_kanban_templates_on_locale'
      t.index [:slug], name: 'index_kanban_templates_on_slug', unique: true
      t.index [:vertical], name: 'index_kanban_templates_on_vertical'
    end

    create_table :kanbans do |t|
      t.string :name, null: false
      t.string :description, limit: 500
      t.string :color, limit: 16
      t.bigint :account_id, null: false
      t.bigint :team_id
      t.jsonb :inbox_ids, default: [], null: false
      t.integer :position, default: 0, null: false
      t.jsonb :settings, default: {}, null: false
      t.datetime :archived_at, precision: nil
      t.bigint :created_by_id
      t.bigint :template_id
      t.timestamps
      t.index %i[account_id archived_at], name: 'index_kanbans_on_account_id_and_archived_at'
      t.index [:account_id], name: 'index_kanbans_on_account_id'
      t.index [:inbox_ids], name: 'index_kanbans_on_inbox_ids', using: :gin
      t.index [:team_id], name: 'index_kanbans_on_team_id'
      t.index [:template_id], name: 'index_kanbans_on_template_id'
    end

    create_table :kanban_stages do |t|
      t.string :name, null: false
      t.string :color, limit: 16
      t.bigint :kanban_id, null: false
      t.integer :position, default: 0, null: false
      t.string :automation_type
      t.integer :rot_after_days
      t.integer :wip_limit
      t.string :won_loss_type
      t.bigint :default_message_template_id
      t.integer :probability
      t.jsonb :settings, default: {}, null: false
      t.timestamps
      t.index %i[kanban_id automation_type], name: 'index_kanban_stages_unique_automation', unique: true, where: '(automation_type IS NOT NULL)'
      t.index %i[kanban_id position], name: 'index_kanban_stages_on_kanban_id_and_position'
      t.index %i[kanban_id won_loss_type], name: 'index_kanban_stages_unique_won_loss', unique: true, where: '(won_loss_type IS NOT NULL)'
      t.index [:kanban_id], name: 'index_kanban_stages_on_kanban_id'
    end

    create_table :kanban_views do |t|
      t.string :name, null: false
      t.bigint :kanban_id, null: false
      t.bigint :user_id
      t.boolean :is_shared, default: false, null: false
      t.jsonb :filters, default: {}, null: false
      t.jsonb :sort, default: { 'by' => 'last_activity_at', 'dir' => 'desc' }, null: false
      t.jsonb :settings, default: {}, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
      t.index %i[kanban_id is_shared], name: 'index_kanban_views_on_kanban_id_and_is_shared'
      t.index %i[kanban_id user_id], name: 'index_kanban_views_on_kanban_id_and_user_id'
      t.index [:kanban_id], name: 'index_kanban_views_on_kanban_id'
      t.index [:user_id], name: 'index_kanban_views_on_user_id'
    end

    create_table :kanban_items do |t|
      t.bigint :kanban_id, null: false
      t.bigint :kanban_stage_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :moved_by_id
      t.datetime :last_stage_change_at, precision: nil
      t.datetime :aging_calculated_at, precision: nil
      t.integer :aging_days, default: 0
      t.decimal :position, precision: 20, scale: 10, default: '0.0'
      t.string :won_reason
      t.string :loss_reason
      t.text :note
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
      t.index [:aging_days], name: 'index_kanban_items_on_aging_days'
      t.index %i[conversation_id kanban_id], name: 'idx_kanban_items_unique', unique: true
      t.index [:conversation_id], name: 'index_kanban_items_on_conversation_id'
      t.index %i[kanban_id created_at], name: 'index_kanban_items_on_kanban_id_and_created_at'
      t.index %i[kanban_id kanban_stage_id position], name: 'idx_kanban_items_stage_pos'
      t.index [:kanban_id], name: 'index_kanban_items_on_kanban_id'
      t.index %i[kanban_stage_id position], name: 'idx_kanban_items_pos_keyset'
      t.index [:kanban_stage_id], name: 'index_kanban_items_on_kanban_stage_id'
      t.index [:last_stage_change_at], name: 'index_kanban_items_on_last_stage_change_at'
      t.index [:moved_by_id], name: 'index_kanban_items_on_moved_by_id'
    end

    create_table :kanban_automations do |t|
      t.string :name, null: false
      t.bigint :kanban_id, null: false
      t.bigint :kanban_stage_id
      t.string :trigger, null: false
      t.jsonb :conditions, default: {}, null: false
      t.jsonb :actions, default: [], null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
      t.index %i[kanban_id enabled], name: 'index_kanban_automations_on_kanban_id_and_enabled'
      t.index [:kanban_id], name: 'index_kanban_automations_on_kanban_id'
      t.index [:kanban_stage_id], name: 'index_kanban_automations_on_kanban_stage_id'
      t.index [:trigger], name: 'index_kanban_automations_on_trigger'
    end

    add_foreign_key :kanban_automations, :kanban_stages, on_delete: :cascade
    add_foreign_key :kanban_automations, :kanbans, on_delete: :cascade
    add_foreign_key :kanban_items, :conversations, on_delete: :cascade
    add_foreign_key :kanban_items, :kanban_stages, on_delete: :restrict
    add_foreign_key :kanban_items, :kanbans, on_delete: :cascade
    add_foreign_key :kanban_items, :users, column: :moved_by_id, on_delete: :nullify
    add_foreign_key :kanban_stages, :kanbans, on_delete: :cascade
    add_foreign_key :kanban_templates, :accounts, on_delete: :cascade
    add_foreign_key :kanban_views, :kanbans, on_delete: :cascade
    add_foreign_key :kanban_views, :users, on_delete: :cascade
    add_foreign_key :kanbans, :accounts
    add_foreign_key :kanbans, :kanban_templates, column: :template_id, on_delete: :nullify
    add_foreign_key :kanbans, :teams, on_delete: :nullify
    add_foreign_key :kanbans, :users, column: :created_by_id, on_delete: :nullify
  end
end
