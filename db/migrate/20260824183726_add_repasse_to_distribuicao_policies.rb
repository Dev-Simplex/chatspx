# Complemento das colunas de repasse. As três primeiras que este PR propunha
# (`repasse_automatico`, `max_repasses`, `pool_esgotado_destino_user_id`) JÁ EXISTEM: entraram
# pela 20260819150000, que está em produção desde 19/08. Recriá-las aqui derrubaria o
# `db:migrate` com "column already exists" e travaria o deploy da frota inteira.
#
# Sobram as duas que são de fato novas, e as duas são do relógio do SLA:
#
# `sla_respeita_horario` decide se o prazo anda 24/7 ou só dentro do expediente do time
# (ver a coluna `horario`, na migration seguinte). Nasce TRUE porque o contrário é o que
# machuca: lead circulando pelo pool de madrugada chega no destino final antes de alguém abrir
# o sistema.
#
# `expirado_conta_como_recebido` é o menos óbvio e o mais importante: com TRUE, quem deixa o
# lead vencer gastou a vez e vai pro fim da fila igual a quem atendeu — a punição vira
# aritmética, sem ninguém precisar aplicar penalidade. Com FALSE, ignorar lead é de graça.
#
# Nota: o PR pedia `max_repasses` default 3; a coluna em produção nasceu com 2 e fica com 2,
# porque mexer no default agora só serviria para divergir das linhas que já existem.
class AddRepasseToDistribuicaoPolicies < ActiveRecord::Migration[7.1]
  def change
    change_table :distribuicao_policies, bulk: true do |t|
      t.boolean :sla_respeita_horario, default: true, null: false
      t.boolean :expirado_conta_como_recebido, default: true, null: false
    end
  end
end
