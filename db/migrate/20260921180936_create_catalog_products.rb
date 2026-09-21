# frozen_string_literal: true

# Catálogo de produtos (C1): o banco do Chat SPX é a FONTE, o catálogo da Meta é espelho.
# Por isso o produto guarda `meta_product_id`/`meta_synced_at` — o vínculo com o item lá fora — e
# não o contrário.
#
# Preço em CENTAVOS: a Meta recebe inteiro em centavos mais a moeda. Guardar decimal aqui obrigaria
# a converter em dois lugares (envio e espelho) e a arredondar promoção na mão.
class CreateCatalogProducts < ActiveRecord::Migration[7.1]
  def change
    criar_categorias
    criar_produtos
  end

  private

  def criar_categorias
    create_table :catalog_categories do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :catalog_categories, [:account_id, :name], unique: true
  end

  def criar_produtos
    create_table :catalog_products do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # Apagar a categoria não pode levar o produto junto: ele volta para "sem categoria".
      t.references :catalog_category, foreign_key: { on_delete: :nullify }, index: true

      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false, default: 0
      t.integer :promo_price_cents
      t.string :currency, null: false, default: 'BRL'
      t.string :sku
      # NULL = não controla estoque. Zero é estoque zerado, que é outra coisa.
      t.integer :stock
      t.boolean :visible, null: false, default: true
      t.boolean :featured, null: false, default: false

      t.string :meta_product_id
      t.datetime :meta_synced_at

      t.timestamps
    end

    # Chave de idempotência do ERP: mandar o mesmo SKU duas vezes atualiza, não duplica. Parcial
    # porque produto cadastrado à mão pode não ter SKU, e vários NULL não podem brigar entre si.
    add_index :catalog_products, [:account_id, :sku], unique: true, where: 'sku IS NOT NULL'
    add_index :catalog_products, [:account_id, :visible]
  end
end
