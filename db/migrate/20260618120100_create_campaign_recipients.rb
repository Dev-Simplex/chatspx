class CreateCampaignRecipients < ActiveRecord::Migration[7.1]
  # Materializa a audiencia de um disparo (lista enviada por upload) como linhas
  # persistidas — fonte de verdade RESUMIVEL da engine, no lugar do Sidekiq
  # ScheduledSet volatil. Cada linha = 1 destinatario + seu status no disparo.
  def change
    create_table :campaign_recipients, if_not_exists: true do |t|
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.bigint :conversation_id
      t.string :phone_number, null: false
      t.string :name
      # Variaveis do template por destinatario (ex.: {"1" => "Maria"}).
      t.jsonb :template_params, default: {}, null: false
      # pending:0 processing:1 sent:2 delivered:3 read:4 failed:5 replied:6 cancelled:7 skipped:8
      t.integer :status, default: 0, null: false
      t.string :external_error
      t.datetime :sent_at
      t.timestamps
    end

    add_index :campaign_recipients, %i[campaign_id status], if_not_exists: true
    add_index :campaign_recipients, %i[account_id phone_number], if_not_exists: true
    add_index :campaign_recipients, :conversation_id, if_not_exists: true
  end
end
