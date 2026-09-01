# Expediente DO TIME, para o relógio do SLA parar fora dele.
#
# Por que não sai da inbox: o Chatwoot tem `working_hours` por INBOX, e na Tozi a inbox
# principal (91, onde a locação atende) está com `working_hours_enabled = false` e os valores
# default de fábrica (9h-17h, seg-sex). O expediente real — 07:30-11:30 e 13:30-17:30, com
# sábado até 11:30 — só existe configurado no `behavior.business_hours` do agente de IA.
# Tirar o relógio da inbox faria o SLA rodar com um horário que ninguém escolheu.
#
# O formato é o MESMO do `behavior.business_hours` de propósito — um formato de expediente no
# produto, não dois:
#   { "timezone" => "America/Cuiaba",
#     "schedule" => [ { "day" => 1, "ranges" => [ { "start" => "07:30", "end" => "11:30" } ] } ] }
#
# Vazio ({}) = time sem expediente configurado. Nesse caso o repasse NÃO age (ver
# JanelaService#prazo): expirar 24/7 mandaria o lead circular pelo pool de madrugada e cair no
# destino final sem ninguém ver. Recusar agir é visível na tela; agir errado às 3h não é.
class AddHorarioToDistribuicaoPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :distribuicao_policies, :horario, :jsonb, default: {}, null: false
  end
end
