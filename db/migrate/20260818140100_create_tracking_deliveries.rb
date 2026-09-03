class CreateTrackingDeliveries < ActiveRecord::Migration[7.1]
  # Bloco 5.03 — uma linha por (evento, destino): cada tentativa de contar o mesmo fato a um destino.
  #
  # O indice unico em (tracking_event_id, destination) e o ACEITE do bloco: e ele que impede entrega
  # dupla. A garantia precisa ser do banco, e nao da aplicacao — dois workers concorrentes lendo antes
  # de escrever criariam duas entregas se a checagem fosse so em Ruby.
  #
  # `field_names` guarda NOMES de campos enviados, nunca valores (T-C8.1). E o que o bloco 5.12
  # verifica para provar que o modo "sem PII" nao vazou nada.
  def change
    create_table :tracking_deliveries do |t|
      t.bigint :tracking_event_id, null: false
      t.integer :destination, null: false
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.integer :http_status
      t.string :error_code
      t.text :error_message
      t.jsonb :field_names, null: false, default: []
      t.decimal :emq, precision: 3, scale: 1
      t.datetime :last_attempted_at
      t.datetime :delivered_at

      t.timestamps

      t.index %i[tracking_event_id destination], unique: true,
                                                 name: 'index_tracking_deliveries_on_event_and_destination'
      # A DLQ do bloco 5.11 e uma consulta por status; sem indice ela varre a tabela inteira.
      t.index :status
    end

    # A entrega nao existe sem o evento: a coluna e NOT NULL, entao CASCADE.
    add_foreign_key :tracking_deliveries, :tracking_events, on_delete: :cascade
  end
end
