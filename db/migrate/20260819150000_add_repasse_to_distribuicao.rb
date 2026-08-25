# Repasse por SLA (SPEC-RODIZIO §7.2): a designação que estoura o prazo sem ninguém assumir
# passa ao PRÓXIMO do rodízio e, esgotadas as tentativas, escala para um responsável fixo.
#
# Até aqui `sla_assumir_minutos` era MEDIDA — a tela do gestor contava "N leads parados há mais
# de X" e nada acontecia. Estas colunas são a AÇÃO, e são CONFIGURAÇÃO, não interruptor: o
# repasse vale para toda política de distribuição ativa, sem flag para ligar.
#
# A única exclusão é por MOTIVO, não por toggle: política com `espelho_vista` não repassa,
# porque o card do lead já existe no Vista no nome do corretor e reescrevê-lo exigiria um
# `CorretorNegocio` novo sobre card existente (não testado) — e o DELETE do Vista responde 401.
# Sem desfazer, errar custa um lead que o corretor já trabalhava. Ver Policy#repassa?.
class AddRepasseToDistribuicao < ActiveRecord::Migration[7.1]
  def change
    change_table :distribuicao_policies, bulk: true do |t|
      # Quantas vezes o lead pode andar antes de escalar. 0 = sem teto.
      t.integer :max_repasses, null: false, default: 2
      # Para quem vai quando o teto estoura ou o pool acaba. Sem destino, a conversa apenas
      # volta a ficar sem dono — inventar um destino seria pior que devolvê-la à fila.
      t.bigint :pool_esgotado_destino_user_id
    end

    # Quantas vezes ESTA designação já foi repassada. Zero = escolha original do Motor. É o
    # contador que o teto (`max_repasses`) lê, e ele viaja na linha do log em vez de numa coluna
    # da conversa porque o ciclo de vida é o da designação, não o da conversa.
    add_column :distribuicao_logs, :repasse_n, :integer, null: false, default: 0
  end
end
