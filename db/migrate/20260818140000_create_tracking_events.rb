class CreateTrackingEvents < ActiveRecord::Migration[7.1]
  # Bloco 5.03 — o registro server-side do FATO. Contrato em docs/tracking/contrato-de-eventos.md.
  #
  # Os dois indices unicos nascem NESTA migration, junto da tabela, e nao numa migration posterior.
  # A razao e operacional: indice unico adicionado depois falha na frota se a tabela ja tiver
  # duplicata, e o banco de teste vazio nunca mostra isso. Como a migration roda em transacao, criar
  # tabela e indice aqui e atomico — a janela em que a duplicata poderia entrar nao existe em
  # ambiente nenhum.
  #
  # ON DELETE segue a doutrina que esta base ja escreveu em
  # 20260723000000_cascade_conversation_deletion_for_orphan_blockers.rb: coluna NOT NULL cujo registro
  # nao existe sem o pai -> CASCADE; coluna nullable de historico de diagnostico -> SET NULL, para que
  # o historico de atribuicao sobreviva E para que apagar a conversa nunca falhe por causa dele.
  def change
    create_events_table
    add_events_foreign_keys
  end

  private

  def create_events_table
    create_table :tracking_events do |t|
      t.string :event_id, null: false
      t.string :name, null: false
      t.bigint :account_id, null: false
      t.bigint :inbox_id
      t.bigint :conversation_id
      t.bigint :contact_id
      t.datetime :occurred_at, null: false
      t.jsonb :properties, null: false, default: {}
      t.integer :source, null: false, default: 0
      t.string :dedup_key, null: false

      t.timestamps

      t.index :conversation_id
      t.index :contact_id
      t.index :inbox_id
    end

    add_events_indexes
  end

  def add_events_indexes
    add_index :tracking_events, :event_id, unique: true
    # A trava de idempotencia do FATO: o job do AsyncDispatcher e retentado, e sem isto o mesmo fato
    # viraria dois eventos com dois event_id — e a dedup por (evento, destino) nao protegeria nada,
    # porque aos olhos do banco seriam eventos diferentes.
    add_index :tracking_events, %i[account_id name dedup_key], unique: true,
                                                               name: 'index_tracking_events_on_dedup'
    add_index :tracking_events, %i[account_id name occurred_at], name: 'index_tracking_events_on_account_name_time'
    # BRIN para varredura por periodo (retencao de 90 dias em 5.14), como reporting_events ja faz.
    add_index :tracking_events, :occurred_at, using: :brin, name: 'index_tracking_events_on_occurred_at_brin'
  end

  def add_events_foreign_keys
    add_foreign_key :tracking_events, :accounts, on_delete: :cascade
    add_foreign_key :tracking_events, :inboxes, on_delete: :nullify
    add_foreign_key :tracking_events, :conversations, on_delete: :nullify
    add_foreign_key :tracking_events, :contacts, on_delete: :nullify
  end
end
