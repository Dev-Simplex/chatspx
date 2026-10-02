# frozen_string_literal: true

# == Schema Information
#
# Table name: catalog_categories
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_catalog_categories_on_account_id           (account_id)
#  index_catalog_categories_on_account_id_and_name  (account_id,name) UNIQUE
#
# Categoria do catálogo. Serve para filtrar a vitrine e agrupar o envio de vários produtos —
# não é hierarquia: coleção e subcategoria ficaram de fora do MVP de propósito.
class CatalogCategory < ApplicationRecord
  belongs_to :account
  # Apagar a categoria devolve o produto para "sem categoria"; a FK do banco faz o mesmo.
  has_many :products, class_name: 'CatalogProduct', dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
end
