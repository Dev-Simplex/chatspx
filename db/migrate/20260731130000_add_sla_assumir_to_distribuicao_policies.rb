# Limiar do SLA-como-medida (docs/clientes/tozi/SPEC-RODIZIO.md §7.2 e §9): a partir de
# quantos minutos uma designação aberta conta como "sem movimento" na tela do gestor.
#
# Em vendas o SLA é MEDIDA, não ação — não repassa nada. Por isso só o limiar entra agora;
# os campos de repasse (repasse_automatico, max_repasses, pool_esgotado_destino) chegam
# junto com a ação, quando ela existir.
#
# Aplicar com alvo específico (db:migrate:up VERSION=20260731130000).
class AddSlaAssumirToDistribuicaoPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :distribuicao_policies, :sla_assumir_minutos, :integer, null: false, default: 30
  end
end
