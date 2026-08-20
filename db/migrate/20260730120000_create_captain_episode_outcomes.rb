class CreateCaptainEpisodeOutcomes < ActiveRecord::Migration[7.1]
  # Additiva. DESFECHO de um episódio (Eval 2.0 F3): uma linha por degrau atingido
  # da escada (respondeu → qualificado → handoff → assumido → visita → venda, mais
  # as saídas esfriou/descartado). Derivado de sinal determinístico que já existe no
  # produto — nenhum degrau aqui vem de LLM.
  #
  # Tabela própria (não coluna no eval) porque desfecho é FATO e veredito é OPINIÃO:
  # o eval é reprocessável (spx:eval:reprocess) e re-julgar não pode apagar o que
  # aconteceu. E porque um episódio atinge N degraus em tempos diferentes — o degrau
  # de cima pode cair dias depois do episódio fechar.
  #
  # Inerte enquanto a conta não tiver custom_attributes['eval_enabled'] = true.
  def up
    create_table :captain_episode_outcomes, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :episode_id, null: false
      # respondeu|qualificado|handoff|assumido|visita|venda|esfriou|descartado
      t.string :degrau, null: false
      # ia|humano|sistema|contato|externo — 'externo' marca o que veio do CRM Vista,
      # onde o SPX sabe atribuir o card ao episódio mas NÃO sabe quem causou.
      t.string :causado_por, null: false
      # user_id (humano) · captain_assistant_id (ia) · nil
      t.bigint :ator_id
      # tool|funnel|mensagem|atributo|vista — a procedência do sinal
      t.string :origem, null: false
      t.jsonb :detalhe, null: false, default: {}
      t.datetime :ocorreu_em, null: false
      # Denormalizado NO MOMENTO DO REGISTRO: esses campos vivem em
      # conversation.custom_attributes e MUDAM. Métrica histórica não pode mudar de
      # valor porque alguém reetiquetou a conversa depois.
      t.string :campanha
      t.string :anuncio
      t.string :publico
      t.string :empreendimento
      t.string :lead_tipo
      t.timestamps
    end

    add_index :captain_episode_outcomes, %i[episode_id degrau], unique: true,
                                                                name: 'idx_cap_ep_outcomes_ep_degrau', if_not_exists: true
    add_index :captain_episode_outcomes, %i[account_id degrau ocorreu_em],
              name: 'idx_cap_ep_outcomes_acct_degrau', if_not_exists: true
    # segmentação da conversão por campanha (a pergunta que originou o F3)
    add_index :captain_episode_outcomes, %i[account_id campanha],
              name: 'idx_cap_ep_outcomes_acct_campanha', if_not_exists: true
    add_index :captain_episode_outcomes, :conversation_id, if_not_exists: true
  end

  def down
    drop_table :captain_episode_outcomes
  end
end
