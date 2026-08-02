# Catálogo de produtos do rodízio (docs/clientes/tozi/SPEC-RODIZIO.md §5.2) + o produto
# resolvido gravado no log da decisão.
#
# Additiva e INERTE: sem produto cadastrado o filtro de pool é no-op e o Motor decide
# exatamente como decidia antes. Aplicar com alvo específico
# (db:migrate:up VERSION=20260730120100) para não disparar migrations destrutivas pendentes.
class CreateDistribuicaoProdutos < ActiveRecord::Migration[7.1]
  def change
    create_table :distribuicao_produtos do |t|
      t.bigint  :account_id, null: false
      t.string  :slug,       null: false
      t.string  :nome,       null: false
      t.boolean :ativo,      null: false, default: true
      # matchers: como reconhecer o produto no lead (empreendimentos, campanhas, palavras...)
      t.jsonb   :matchers,   null: false, default: {}
      # vista: defaults do card (pipe, etapa, veiculo_captacao, prefixo_nome_negocio).
      # Consumido pelo espelho do Vista — evita hardcodar pipe/etapa no serviço.
      t.jsonb   :vista,      null: false, default: {}
      t.timestamps
    end
    add_index :distribuicao_produtos, %i[account_id slug], unique: true

    # Por que o produto entra no log: sem ele não dá pra explicar um `sem_pool` causado
    # pelo filtro de produto ("ninguém do pool atende isso") — que é o modo de falha novo.
    add_column :distribuicao_logs, :produto_slug, :string
  end
end
