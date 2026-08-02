class AddCanonicalPhoneToCampaignRecipients < ActiveRecord::Migration[7.1]
  # Chave canonica do destinatario = DDD + ultimos 8 digitos. E o que colapsa as
  # variantes do 9o digito e do DDI (`+5566992927211` == `+556692927211`), tornando
  # possivel deduplicar de verdade: dentro da lista, contra o historico de disparos
  # da conta e contra a blacklist. Sem ela a deduplicacao era pela string e164 e as
  # variantes do mesmo numero passavam como pessoas diferentes.
  def up
    add_column :campaign_recipients, :canonical_phone, :string, if_not_exists: true
    add_index :campaign_recipients, %i[account_id canonical_phone], if_not_exists: true

    # Backfill dos existentes: phone_number ja esta em e164 (+55DDD[9]XXXXXXXX),
    # entao a canonica sai por SQL puro — DDD (2 digitos apos o 55) + os 8 finais.
    execute <<~SQL.squish
      UPDATE campaign_recipients
         SET canonical_phone = substr(regexp_replace(phone_number, '\\D', '', 'g'), 3, 2)
                            || right(regexp_replace(phone_number, '\\D', '', 'g'), 8)
       WHERE canonical_phone IS NULL
         AND phone_number LIKE '+55%'
         AND length(regexp_replace(phone_number, '\\D', '', 'g')) BETWEEN 12 AND 13
    SQL
  end

  def down
    remove_index :campaign_recipients, %i[account_id canonical_phone], if_exists: true
    remove_column :campaign_recipients, :canonical_phone, if_exists: true
  end
end
