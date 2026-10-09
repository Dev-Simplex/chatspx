class AddTrackingToCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    # O destinatário parava em `sent`: daqui em diante ele guarda a mensagem do template, o
    # carimbo de cada etapa e o `pricing` que a Meta manda no status (e era descartado).
    add_column :campaign_recipients, :message_id, :bigint, if_not_exists: true
    add_column :campaign_recipients, :delivered_at, :datetime, if_not_exists: true
    add_column :campaign_recipients, :read_at, :datetime, if_not_exists: true
    add_column :campaign_recipients, :replied_at, :datetime, if_not_exists: true
    add_column :campaign_recipients, :failed_at, :datetime, if_not_exists: true
    add_column :campaign_recipients, :pricing, :jsonb, default: {}, null: false, if_not_exists: true

    add_index :campaign_recipients, :message_id, if_not_exists: true
    # A resposta é atribuída pelo contato (ela pode chegar numa conversa nova), e o ouvinte
    # roda a cada mensagem recebida da instância: sem índice seria varredura da tabela.
    add_index :campaign_recipients, [:contact_id, :sent_at], if_not_exists: true
  end
end
