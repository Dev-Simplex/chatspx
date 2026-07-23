class CreateConversationTakeoverRequests < ActiveRecord::Migration[7.0]
  def change
    create_requests_table
    add_request_indexes
    add_request_foreign_keys
  end

  private

  def create_requests_table
    create_table :conversation_takeover_requests, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :requester_id, null: false
      # SNAPSHOT do dono no momento do pedido — NÃO ler conversation.assignee_id
      # depois. Se a conversa trocar de mãos por outro caminho, precisamos saber
      # contra QUEM o pedido foi feito; o assignee atual responde outra pergunta.
      t.bigint :owner_id
      t.integer :status, null: false, default: 0
      t.integer :resolution_source
      t.text :reason
      t.text :response_note
      t.bigint :responded_by_id
      t.datetime :responded_at
      t.timestamps
    end
  end

  def add_request_indexes
    # Único PARCIAL: impede o MESMO agente pedir 2x a mesma conversa, mas PERMITE
    # agentes diferentes pedirem a mesma (o dono escolhe), e não bloqueia um novo
    # pedido depois de cancelled/denied. status 0 = pending.
    add_index :conversation_takeover_requests,
              %i[conversation_id requester_id],
              unique: true,
              where: 'status = 0',
              name: 'idx_takeover_requests_unique_pending',
              if_not_exists: true

    # "preciso responder" / "meus pedidos" / admin
    add_index :conversation_takeover_requests, %i[owner_id status],
              name: 'idx_takeover_requests_owner_status', if_not_exists: true
    add_index :conversation_takeover_requests, %i[requester_id status],
              name: 'idx_takeover_requests_requester_status', if_not_exists: true
    add_index :conversation_takeover_requests, %i[account_id status],
              name: 'idx_takeover_requests_account_status', if_not_exists: true
    add_index :conversation_takeover_requests, :conversation_id,
              name: 'idx_takeover_requests_conversation', if_not_exists: true
  end

  def add_request_foreign_keys
    add_foreign_key :conversation_takeover_requests, :accounts, on_delete: :cascade unless foreign_key_exists?(
      :conversation_takeover_requests, :accounts
    )
    add_foreign_key :conversation_takeover_requests, :conversations, on_delete: :cascade unless foreign_key_exists?(
      :conversation_takeover_requests, :conversations
    )
    # nullify (não cascade) no requester/owner: um agente sair da conta NÃO pode
    # apagar o histórico do pedido. O agents/destroy_job supersede os pendentes.
    add_foreign_key :conversation_takeover_requests, :users, column: :requester_id, on_delete: :nullify unless foreign_key_exists?(
      :conversation_takeover_requests, :users, column: :requester_id
    )
    add_foreign_key :conversation_takeover_requests, :users, column: :owner_id, on_delete: :nullify unless foreign_key_exists?(
      :conversation_takeover_requests, :users, column: :owner_id
    )
    add_foreign_key :conversation_takeover_requests, :users, column: :responded_by_id, on_delete: :nullify unless foreign_key_exists?(
      :conversation_takeover_requests, :users, column: :responded_by_id
    )
  end
end
