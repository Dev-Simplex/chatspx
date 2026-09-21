# frozen_string_literal: true

# == Schema Information
#
# Table name: catalog_products
#
#  id                  :bigint           not null, primary key
#  currency            :string           not null, default("BRL")
#  description         :text
#  featured            :boolean          not null, default(FALSE)
#  meta_synced_at      :datetime
#  name                :string           not null
#  price_cents         :integer          not null, default(0)
#  promo_price_cents   :integer
#  sku                 :string
#  stock               :integer
#  visible             :boolean          not null, default(TRUE)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  catalog_category_id :bigint
#  meta_product_id     :string
#
# Indexes
#
#  index_catalog_products_on_account_id              (account_id)
#  index_catalog_products_on_account_id_and_sku      (account_id,sku) UNIQUE WHERE (sku IS NOT NULL)
#  index_catalog_products_on_account_id_and_visible  (account_id,visible)
#  index_catalog_products_on_catalog_category_id     (catalog_category_id)
#
# Produto do catálogo. O banco daqui é a FONTE; o catálogo da Meta é espelho (`meta_product_id`
# guarda o item de lá, `meta_synced_at` diz quando ele foi conferido pela última vez).
#
# Preço em CENTAVOS, com moeda: é o formato que a Meta recebe. Decimal aqui obrigaria a converter
# no envio e no espelho, e arredondaria promoção na mão.
class CatalogProduct < ApplicationRecord
  belongs_to :account
  belongs_to :category, class_name: 'CatalogCategory', foreign_key: :catalog_category_id, optional: true, inverse_of: :products

  # A PRIMEIRA imagem é a capa — é ela que vai na bolha da conversa e no espelho da Meta.
  has_many_attached :images

  validates :name, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :promo_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, presence: true
  # Chave de idempotência do ERP. `allow_nil` porque produto cadastrado à mão pode não ter SKU.
  validates :sku, uniqueness: { scope: :account_id, case_sensitive: false }, allow_nil: true

  before_validation :limpar_sku

  scope :visiveis, -> { where(visible: true) }
  scope :em_destaque, -> { where(featured: true) }
  scope :da_categoria, ->(id) { where(catalog_category_id: id) }
  # Espelho desatualizado: nunca sincronizado, ou mexido depois da última sincronização.
  scope :para_sincronizar, -> { where(meta_synced_at: nil).or(where('meta_synced_at < catalog_products.updated_at')) }

  # O preço que vale hoje: a promoção vence o cheio quando existe.
  def preco_atual_cents
    promo_price_cents.presence || price_cents
  end

  def em_promocao?
    promo_price_cents.present? && promo_price_cents < price_cents
  end

  def capa
    images.first
  end

  # Carimbo do espelho, com `update_columns` DE PROPÓSITO: gravar por `update!` moveria o
  # `updated_at` no mesmo salvar, o carimbo nasceria mais velho que o registro e o produto nunca
  # sairia de `para_sincronizar` — a sincronização reenviaria o catálogo inteiro para sempre.
  def marcar_sincronizado!(id_na_meta)
    update_columns(meta_product_id: id_na_meta, meta_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  # Espaço em volta do SKU vindo do ERP transformaria " ABC" e "ABC" em dois produtos, furando a
  # idempotência que o índice único deveria garantir. String vazia vira NULL pelo mesmo motivo.
  def limpar_sku
    self.sku = sku&.strip.presence
  end
end
