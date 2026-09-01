# Repasse por SLA (SPEC-RODIZIO §7.2): a designação que estoura o prazo sem ninguém assumir
# passa ao PRÓXIMO do rodízio e, esgotadas as tentativas, escala para um responsável fixo.
#
# Até aqui `sla_assumir_minutos` era MEDIDA — a tela do gestor contava "N leads parados há mais
# de X" e nada acontecia. A amarra que segurou a AÇÃO é da conta 6 (repassar exigiria reescrever
# o CorretorNegocio de um card já criado no Vista, e o DELETE de lá responde 401). Estes campos
# tornam a ação POSSÍVEL sem torná-la automática: `repasse_automatico` nasce FALSE, então quem já
# roda hoje continua exatamente como está — a conta 6 segue só medindo.
#
# `gatilho_sem_ia` é ortogonal e também opt-in: hoje o Motor só é chamado no handoff do Captain
# (HumanHandoffService), então um time que recebe conversa por flow/regra (`assign_team`) nunca
# distribui. Ligado, o TEAM_CHANGED passa a acionar o Motor.
class AddRepasseToDistribuicao < ActiveRecord::Migration[7.1]
  def change
    change_table :distribuicao_policies, bulk: true do |t|
      t.boolean :repasse_automatico, null: false, default: false
      t.integer :max_repasses, null: false, default: 2
      t.bigint :pool_esgotado_destino_user_id
      t.boolean :gatilho_sem_ia, null: false, default: false
    end

    # Quantas vezes ESTA designação já foi repassada. Zero = escolha original do Motor. É o
    # contador que o teto (`max_repasses`) lê, e ele viaja na linha do log em vez de numa coluna
    # da conversa porque o ciclo de vida é o da designação, não o da conversa.
    add_column :distribuicao_logs, :repasse_n, :integer, null: false, default: 0
  end
end
