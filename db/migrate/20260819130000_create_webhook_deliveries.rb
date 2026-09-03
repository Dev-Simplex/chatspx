# Bloco 4.14 — o log de entregas, que e o que torna o replay possivel.
#
# Tabela NOVA: nao ha linha existente para violar restricao, entao aqui NOT NULL e default
# sao seguros — o perigo da cicatriz e acrescentar restricao sobre dado que ja existe.
#
# `delivery_id` NAO e unico: o reenvio reusa o MESMO id de proposito, para o destino
# conseguir deduplicar. Um indice unico ali proibiria justamente o replay.
class CreateWebhookDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_deliveries do |t|
      t.references :webhook, null: false, foreign_key: true, index: false
      t.bigint :account_id, null: false
      t.string :delivery_id, null: false
      t.string :event
      t.integer :status, null: false, default: 0
      t.integer :http_status
      t.integer :attempts, null: false, default: 1
      t.text :error_message
      t.jsonb :payload, null: false, default: {}
      t.datetime :delivered_at
      t.timestamps
    end

    # A consulta da tela: as entregas deste webhook, mais recentes primeiro.
    add_index :webhook_deliveries, %i[webhook_id created_at], order: { created_at: :desc }
    # O replay chega pelo delivery_id; a retencao varre por created_at.
    add_index :webhook_deliveries, %i[account_id delivery_id]
    add_index :webhook_deliveries, :created_at
  end
end
