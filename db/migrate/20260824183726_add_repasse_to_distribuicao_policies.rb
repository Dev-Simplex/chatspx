# O `sla_assumir_minutos` já existia e só MEDIA: a tela mostrava "12 leads designados há mais de
# 2h" e nada acontecia. Estes campos são o que transforma o SLA em ação, sem tirar de ninguém a
# opção de continuar só medindo — `repasse_automatico` nasce FALSE, então nenhuma política
# existente muda de comportamento ao migrar.
#
# `expirado_conta_como_recebido` é o menos óbvio e o mais importante: com TRUE, quem deixa o lead
# vencer gastou a vez e vai pro fim da fila igual a quem atendeu — a punição vira aritmética, sem
# ninguém precisar aplicar penalidade. Com FALSE, ignorar lead é de graça.
class AddRepasseToDistribuicaoPolicies < ActiveRecord::Migration[7.1]
  def change
    change_table :distribuicao_policies, bulk: true do |t|
      t.boolean :repasse_automatico, default: false, null: false
      t.integer :max_repasses, default: 3, null: false
      t.boolean :sla_respeita_horario, default: true, null: false
      t.boolean :expirado_conta_como_recebido, default: true, null: false
      # Dono final quando o lead esgota os repasses. Sem ele o lead circula para sempre, que é o
      # mesmo que ninguém ser responsável. Nulo = comportamento de hoje (para de repassar e fica).
      t.bigint :pool_esgotado_destino_user_id
    end
  end
end
