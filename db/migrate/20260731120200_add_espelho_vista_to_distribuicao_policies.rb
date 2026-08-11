# Espelho do Vista atrás de flag POR TIME (docs/clientes/tozi/SPEC-RODIZIO.md §5.1 e §8).
#
# Default `false`: o espelho é paliativo enquanto o corretor não vive no SPX, e desligá-lo
# tem que ser configuração, não deploy.
#
# `vista_padrao` guarda os defaults do card (pipe, etapa, veiculo_captacao, interesse,
# prefixo_nome_negocio) para o lead SEM produto identificado — sem isso ele seria designado
# e o corretor nunca ficaria sabendo. O produto, quando existe, tem precedência.
#
# Additiva e inerte. Aplicar com alvo específico
# (db:migrate:up VERSION=20260731120200) para não disparar migrations destrutivas pendentes.
class AddEspelhoVistaToDistribuicaoPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :distribuicao_policies, :espelho_vista, :boolean, null: false, default: false
    add_column :distribuicao_policies, :vista_padrao, :jsonb, null: false, default: {}
  end
end
