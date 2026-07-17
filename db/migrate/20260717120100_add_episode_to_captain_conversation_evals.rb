class AddEpisodeToCaptainConversationEvals < ActiveRecord::Migration[7.1]
  # O eval passa a poder apontar pra um EPISÓDIO (Eval 2.0 F1): N evals por conversa
  # (1 por episódio). O unique de conversation_id vira índice comum; a unicidade real
  # passa a ser por episódio (parcial). Evals antigos (episode_id nil) seguem válidos.
  def up
    add_column :captain_conversation_evals, :episode_id, :bigint, if_not_exists: true
    add_index :captain_conversation_evals, :episode_id, unique: true,
                                           where: 'episode_id IS NOT NULL',
                                           name: 'idx_cap_conv_evals_on_episode', if_not_exists: true

    remove_index :captain_conversation_evals, name: 'idx_cap_conv_evals_on_conversation', if_exists: true
    add_index :captain_conversation_evals, :conversation_id,
              name: 'idx_cap_conv_evals_on_conversation', if_not_exists: true
  end

  def down
    remove_index :captain_conversation_evals, name: 'idx_cap_conv_evals_on_episode', if_exists: true
    remove_column :captain_conversation_evals, :episode_id, if_exists: true
    # o unique original só volta se não houver múltiplos evals por conversa
    remove_index :captain_conversation_evals, name: 'idx_cap_conv_evals_on_conversation', if_exists: true
    add_index :captain_conversation_evals, :conversation_id, unique: true,
              name: 'idx_cap_conv_evals_on_conversation', if_not_exists: true
  end
end
