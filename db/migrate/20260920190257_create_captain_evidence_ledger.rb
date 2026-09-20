# Atomic ledger schema. Facts inherit observed_at from their source; rows have no mutable updated_at.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Rails/CreateTableWithTimestamps
class CreateCaptainEvidenceLedger < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_evidence_sources do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :captain_assistant_id
      t.string :episode_key, null: false
      t.string :turn_id, null: false
      t.string :run_id, null: false
      t.string :origin, null: false
      t.string :source_name, null: false
      t.string :source_version, null: false
      t.string :status, null: false
      t.jsonb :full_result, null: false
      t.string :digest, null: false
      t.datetime :observed_at, null: false, precision: 6
      t.datetime :expires_at, precision: 6
      t.datetime :created_at, null: false, precision: 6
    end
    add_index :captain_evidence_sources, [:account_id, :conversation_id, :episode_key, :id],
              unique: true, name: 'idx_evidence_source_identity'

    create_table :captain_evidence_facts do |t|
      t.bigint :source_id, null: false
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.string :episode_key, null: false
      t.string :entity_type, null: false
      t.string :entity_id, null: false
      t.jsonb :aliases, null: false, default: []
      t.string :field, null: false
      t.string :value_type, null: false
      t.jsonb :value, null: false
      t.string :unit, null: false
      t.string :assertion_scope, null: false, default: 'business'
      t.jsonb :dependencies, null: false, default: []
    end
    add_index :captain_evidence_facts, [:account_id, :conversation_id, :episode_key], name: 'idx_evidence_facts_episode'
    add_index :captain_evidence_facts, :source_id
    add_foreign_key :captain_evidence_facts, :captain_evidence_sources,
                    column: [:account_id, :conversation_id, :episode_key, :source_id],
                    primary_key: [:account_id, :conversation_id, :episode_key, :id], on_delete: :cascade

    create_table :captain_fact_guard_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :captain_assistant_id
      t.bigint :message_id
      t.string :episode_key, null: false
      t.string :turn_id, null: false
      t.string :run_id, null: false
      t.string :publication_id, null: false
      t.string :publication_path, null: false
      t.string :stage, null: false
      t.string :extractor_version, null: false
      t.string :fact_type, null: false
      t.string :decision, null: false
      t.string :reason, null: false
      t.jsonb :claim, null: false, default: {}
      t.jsonb :evidence_ids, null: false, default: []
      t.string :payload_digest, null: false
      t.float :duration_ms, null: false
      t.datetime :created_at, null: false, precision: 6
    end
    add_index :captain_fact_guard_events, [:account_id, :created_at], name: 'idx_fact_guard_reporting'
    add_index :captain_fact_guard_events, :publication_id
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Rails/CreateTableWithTimestamps
