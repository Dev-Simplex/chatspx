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
  # Mesma receita de `Attachment` e `Avatarable`: sem os helpers de rota aqui, `url_for` na view
  # devolve caminho RELATIVO, e a Meta (C9) precisa de URL absoluta para buscar a foto.
  include Rails.application.routes.url_helpers

  # Propósito do `signed_id` da foto pública (C9). Assinatura com propósito impede que o mesmo id
  # sirva para outra rota assinada do sistema.
  IMAGEM_PUBLICA = :catalog_public_image

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

  # Webhooks do catálogo (C4). `after_*_commit` porque avisar antes do commit entregaria ao ERP um
  # produto que ainda pode não existir. O carimbo do espelho da Meta usa `update_columns` e não
  # passa por aqui de propósito: sincronizar não é mudança de produto.
  after_create_commit :avisar_criado
  after_update_commit :avisar_alteracoes
  after_destroy_commit :avisar_removido

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

  def capa_url
    capa ? url_for(capa) : nil
  end

  # URL da capa para a META, e só para ela. É outra coisa do `capa_url`: aquele é o link assinado
  # do ActiveStorage, que em produção morre em 30 minutos
  # (`config.active_storage.service_urls_expire_in`, que existe por causa de vídeo grande em
  # conversa e não vai mudar). A Meta busca a `image_url` uma vez e faz CACHE dela, então link que
  # expira aparece depois como "a foto sumiu do catálogo".
  #
  # O identificador é o `signed_id` sem expiração: estável entre as passadas do espelho (o
  # verificador é determinístico) e adivinhável só por quem tem o link — `/:account_id/:product_id`
  # cru deixaria o catálogo inteiro de qualquer conta enumerável.
  def public_image_url
    return nil unless visible && capa.present?

    catalog_public_image_url(id: signed_id(purpose: IMAGEM_PUBLICA, expires_in: nil))
  end

  def imagens_para_api
    images.map { |imagem| { id: imagem.id, url: url_for(imagem), filename: imagem.filename.to_s } }
  end

  def webhook_data
    {
      id: id, account_id: account_id, sku: sku, name: name, description: description,
      price_cents: price_cents, promo_price_cents: promo_price_cents,
      current_price_cents: preco_atual_cents, currency: currency,
      stock: stock, visible: visible, featured: featured,
      categoria: category&.name, cover_url: capa_url,
      meta_product_id: meta_product_id, updated_at: updated_at
    }
  end

  # Chamado pela C8 quando o atendente manda o produto na conversa. Mora aqui, e não no serviço de
  # envio, para o contrato do evento ficar num lugar só.
  def avisar_enviado_no_chat(conversation_id:, message_id: nil)
    disparar(Events::Types::CATALOGO_PRODUTO_ENVIADO,
             extras: { conversation_id: conversation_id, message_id: message_id })
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

  def avisar_criado
    disparar(Events::Types::CATALOGO_PRODUTO_CRIADO)
  end

  # Três avisos diferentes podem sair do mesmo salvar, e é o que o ERP precisa:
  # - tirar de visível é REMOÇÃO do ponto de vista dele (é o que o DELETE da C3 faz);
  # - estoque tem evento próprio, porque é o que muda toda hora e o que dispara reposição;
  # - o resto é atualização comum.
  def avisar_alteracoes
    avisar_estoque if saved_change_to_stock?

    # Desativar É remoção para o ERP (é o que o DELETE da C3 faz), e sai como UM aviso só: mandar
    # "removido" e "atualizado" no mesmo salvar encheria a fila dele com evento redundante.
    if virou_invisivel?
      avisar_removido
    elsif mudou_alem_do_estoque?
      disparar(Events::Types::CATALOGO_PRODUTO_ATUALIZADO)
    end
  end

  def avisar_estoque
    anterior, atual = saved_change_to_stock
    disparar(Events::Types::CATALOGO_ESTOQUE_ALTERADO,
             extras: { estoque_anterior: anterior, estoque_atual: atual })
  end

  def virou_invisivel?
    saved_change_to_visible? && !visible
  end

  def mudou_alem_do_estoque?
    (saved_changes.keys - %w[stock updated_at]).any?
  end

  def avisar_removido
    disparar(Events::Types::CATALOGO_PRODUTO_REMOVIDO)
  end

  # O payload é montado AQUI, no instante do evento, e viaja pronto. Mandar o registro e deixar o
  # listener ler depois entregava o estado ATUAL do produto: o "produto.criado" chegava com o preço
  # de um update posterior, e o "estoque.alterado" já vinha invisível. Para um contrato com ERP
  # isso é dado errado, não atraso.
  #
  # `event_at` vai junto porque a fila é assíncrona e a ordem de entrega não é garantida — é por
  # ele que o cliente ordena e descarta evento velho.
  def disparar(evento, extras: nil)
    agora = Time.zone.now
    payload = webhook_data.merge(event: evento, event_at: agora.iso8601(3)).merge(extras || {})
    Rails.configuration.dispatcher.dispatch(evento, agora, payload: payload, account_id: account_id)
  end
end
