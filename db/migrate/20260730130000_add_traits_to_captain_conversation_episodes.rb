class AddTraitsToCaptainConversationEpisodes < ActiveRecord::Migration[7.1]
  # Additiva. TRAÇOS DE CONDUTA do episódio (Eval 2.0 F3): as características
  # mensuráveis de COMO o atendimento foi conduzido. Sozinho, o desfecho não responde
  # nada — é o cruzamento conduta × desfecho, segmentado por campanha, que responde
  # "no público X, resposta mais curta converte mais?".
  #
  # Moram no episódio (e não em tabela própria) porque são 1:1 com ele, imutáveis
  # depois que ele fecha e da mesma natureza do `mensagens`, que já vive aqui. O
  # EpisodeSegmenterService atribui uma lista explícita de colunas, então re-segmentar
  # NÃO apaga estes campos; e se o episódio for destruído, os traços vão junto — que
  # é o certo, já que a fronteira mudou.
  #
  # Nulos = ainda não calculados (episódios anteriores ao backfill spx:eval:outcomes).
  def up
    change_table :captain_conversation_episodes, bulk: true do |t|
      t.integer :turnos_ia
      t.integer :turnos_cliente
      # média de caracteres das respostas da IA — o traço central da pergunta
      t.integer :chars_resposta_media
      t.integer :ferramentas_usadas
      t.boolean :enviou_midia
      t.integer :duracao_segundos
      # Dimensão de segmentação no PRÓPRIO episódio, além da cópia que vai em cada
      # linha de desfecho. Não é duplicação à toa: episódio sem NENHUM desfecho (HSM
      # enviado, lead nunca respondeu) não tem linha em captain_episode_outcomes e
      # sumiria da análise — justamente o denominador de "o opener funcionou". Com a
      # campanha aqui, o episódio é a unidade e a taxa de conversão tem denominador
      # honesto.
      t.string :campanha
    end

    add_index :captain_conversation_episodes, %i[account_id campanha],
              name: 'idx_cap_conv_episodes_acct_campanha', if_not_exists: true
  end

  def down
    remove_index :captain_conversation_episodes, name: 'idx_cap_conv_episodes_acct_campanha', if_exists: true
    change_table :captain_conversation_episodes, bulk: true do |t|
      t.remove :turnos_ia, :turnos_cliente, :chars_resposta_media,
               :ferramentas_usadas, :enviou_midia, :duracao_segundos, :campanha
    end
  end
end
