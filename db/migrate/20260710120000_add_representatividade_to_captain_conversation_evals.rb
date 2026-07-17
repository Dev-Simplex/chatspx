class AddRepresentatividadeToCaptainConversationEvals < ActiveRecord::Migration[7.1]
  # Additiva. Marca se a conversa é um atendimento real de cliente (em escopo) ou
  # ruído (interno/outra_empresa/bot/teste/sem_atendimento) — o eval passa a excluir
  # o ruído das métricas. Default 'atendimento_real' mantém os evals antigos em escopo
  # até serem reprocessados (spx:eval:reprocess). Inerte fora do eval.
  def up
    add_column :captain_conversation_evals, :representatividade, :string,
               null: false, default: 'atendimento_real', if_not_exists: true
    add_index :captain_conversation_evals, :representatividade, if_not_exists: true
  end

  def down
    remove_column :captain_conversation_evals, :representatividade, if_exists: true
  end
end
