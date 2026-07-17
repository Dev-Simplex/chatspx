class CreateCaptainConversationEpisodes < ActiveRecord::Migration[7.1]
  # Additiva. Episódio de atendimento = unidade de avaliação do eval (Eval 2.0 F1).
  # A conversa perpétua do WhatsApp é segmentada em episódios por fronteiras
  # determinísticas (resolve→reopen, HSM de campanha, gap de inatividade).
  # Inerte enquanto nenhuma conta tiver custom_attributes['eval_unit'] = 'episode'.
  def up
    create_table :captain_conversation_episodes, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.integer :seq, null: false
      t.bigint :first_message_id, null: false
      t.bigint :last_message_id, null: false
      t.datetime :started_at, null: false
      t.datetime :last_message_at, null: false
      # nil = episódio ainda aberto (em andamento)
      t.datetime :ended_at
      # o que FECHOU o episódio: resolve | gap | hsm_campanha | aberto (ainda não fechou)
      t.string :boundary_reason, null: false, default: 'aberto'
      t.integer :mensagens, null: false, default: 0
      # versão das regras de segmentação — permite re-segmentar comparável
      t.integer :segmenter_version, null: false, default: 1
      t.timestamps
    end

    add_index :captain_conversation_episodes, %i[conversation_id seq], unique: true,
                                              name: 'idx_cap_conv_episodes_conv_seq', if_not_exists: true
    add_index :captain_conversation_episodes, :account_id, if_not_exists: true
    add_index :captain_conversation_episodes, %i[account_id ended_at], if_not_exists: true
    # sweep de episódios abertos vencidos por gap
    add_index :captain_conversation_episodes, :last_message_at, if_not_exists: true
  end

  def down
    drop_table :captain_conversation_episodes
  end
end
