class CreateCaptainToolCalls < ActiveRecord::Migration[7.1]
  # Additiva. Trace de tool calls da IA (Eval 2.0 F2): o que cada ferramenta recebeu
  # e devolveu, por conversa — a fundação do eval de ferramentas (o juiz passa a ver
  # o que a tool retornou; o gate determinístico compara retorno × resposta).
  # Só grava em contas com eval_enabled — inerte nas demais.
  def up
    create_table :captain_tool_calls, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :captain_assistant_id
      t.string :tool_name, null: false
      t.jsonb :args, null: false, default: {}
      # resultado truncado (auditoria/juiz) — nunca o payload inteiro
      t.text :result_preview
      t.string :status, null: false, default: 'ok' # ok | error
      t.string :error
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end

    add_index :captain_tool_calls, %i[conversation_id created_at], if_not_exists: true
    add_index :captain_tool_calls, %i[account_id created_at], if_not_exists: true
  end

  def down
    drop_table :captain_tool_calls
  end
end
