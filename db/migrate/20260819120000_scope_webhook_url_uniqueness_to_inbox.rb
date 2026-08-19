# Bloco 4.13 — a unicidade de URL passa a considerar a inbox.
#
# Enquanto o `inbox_id` era letra morta, "uma URL por conta" fazia sentido: o webhook
# recebia tudo de qualquer jeito, entao dois registros com a mesma URL seriam duplicata
# pura. Com o filtro por inbox funcionando, apontar a MESMA URL para duas inboxes
# diferentes vira configuracao legitima — e o indice antigo a proibia.
#
# Esta migration RELAXA uma restricao, e essa direcao e segura sobre dado existente: toda
# linha valida sob (account_id, url) continua valida sob (account_id, url, inbox_id). O
# caminho contrario — apertar — e o que falha em producao e passa no banco de teste vazio.
#
# NULLS NOT DISTINCT para o Postgres tratar dois webhooks sem inbox e com a mesma URL como
# duplicata, que e o que a regra antiga ja garantia. Sem isso, o relaxamento abriria uma
# brecha: `NULL <> NULL` deixaria passar N registros identicos sem inbox.
class ScopeWebhookUrlUniquenessToInbox < ActiveRecord::Migration[7.1]
  def up
    remove_index :webhooks, %i[account_id url], name: 'index_webhooks_on_account_id_and_url'
    add_index :webhooks, %i[account_id url inbox_id],
              unique: true, nulls_not_distinct: true,
              name: 'index_webhooks_on_account_id_url_and_inbox_id'
  end

  def down
    remove_index :webhooks, %i[account_id url inbox_id], name: 'index_webhooks_on_account_id_url_and_inbox_id'
    add_index :webhooks, %i[account_id url], unique: true, name: 'index_webhooks_on_account_id_and_url'
  end
end
