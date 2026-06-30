class CreateAccountIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :account_integrations do |t|
      t.bigint :account_id, null: false
      t.string :provider, null: false
      t.boolean :enabled, null: false, default: false
      # TEXT (not jsonb) so the column can be transparently encrypted via
      # `encrypts :settings` when Active Record Encryption keys are configured.
      # Falls back to plaintext JSON otherwise. See app/models/account_integration.rb.
      t.text :settings

      t.timestamps
    end

    add_index :account_integrations, :account_id
    add_index :account_integrations, [:account_id, :provider],
              unique: true,
              name: 'index_account_integrations_on_account_id_and_provider'
  end
end
