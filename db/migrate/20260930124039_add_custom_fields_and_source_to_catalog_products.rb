# frozen_string_literal: true

# Catálogo v2: campos personalizados por conta, origem do item (integração) e preço opcional.
# Item que já existe com preço 0 continua com 0: sem backfill de propósito.
class AddCustomFieldsAndSourceToCatalogProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :catalog_products, :custom_attributes, :jsonb, null: false, default: {}
    add_column :catalog_products, :source, :string
    add_column :catalog_products, :external_id, :string
    add_column :catalog_products, :external_image_url, :string
    add_index  :catalog_products, [:account_id, :source, :external_id], unique: true, where: 'external_id IS NOT NULL'
    change_column_null    :catalog_products, :price_cents, true
    change_column_default :catalog_products, :price_cents, from: 0, to: nil
  end
end
