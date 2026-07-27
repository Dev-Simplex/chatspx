class CreateCaptainConversationEvals < ActiveRecord::Migration[7.1]
  # Tabela additiva do sistema de eval (LLM-as-a-Judge). Um registro por conversa
  # avaliada (upsert por conversation_id). Guarda o veredito do arco + a auditoria
  # resposta-a-resposta em response_findings (jsonb). Inerte enquanto nenhuma conta
  # tiver custom_attributes['eval_enabled'] = true.
  def up
    create_table :captain_conversation_evals, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :captain_assistant_id
      # veredito do arco (a conversa inteira)
      t.string :interesse
      t.string :intencao
      t.string :funil
      t.string :conduzido_por
      t.string :handoff_timing
      t.integer :nota
      t.text :resumo
      t.jsonb :objecoes, null: false, default: []
      # auditoria resposta-a-resposta: [{resposta_num, message_id, quem, categoria, severidade, trecho, porque}]
      t.jsonb :response_findings, null: false, default: []
      # veredito bruto do LLM (auditoria/replay)
      t.jsonb :veredito_raw, null: false, default: {}
      # nº de mensagens no momento do eval — se aumentar, a conversa precisa reavaliar
      t.integer :mensagens_avaliadas, null: false, default: 0
      t.datetime :avaliado_em
      t.timestamps
    end

    add_index :captain_conversation_evals, :account_id, if_not_exists: true
    add_index :captain_conversation_evals, :conversation_id, unique: true,
                                           name: 'idx_cap_conv_evals_on_conversation', if_not_exists: true
    add_index :captain_conversation_evals, :captain_assistant_id, if_not_exists: true
    add_index :captain_conversation_evals, :avaliado_em, if_not_exists: true
  end

  def down
    drop_table :captain_conversation_evals
  end
end
