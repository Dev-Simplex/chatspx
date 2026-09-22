# frozen_string_literal: true

# Monta o objeto `interactive` de PRODUTO da Meta (C9). Só monta: o envio já existe e roda em
# produção — qualquer payload gravado em `content_attributes['interactive_payload']` sai por
# `Whatsapp::Providers::WhatsappCloudService#send_raw_interactive`. Caminho de envio novo aqui seria
# duplicar o que já funciona.
#
# CONTRATO COM A C8 (ela faz a UI e a bolha):
#
#   payload = Catalog::MetaMessageBuilder.new(conversation: conversa, produtos: [produto]).perform
#   Messages::MessageBuilder.new(autor, conversa,
#                                content_attributes: { 'interactive_payload' => payload }).perform
#
# `corpo:` e `cabecalho:` são opcionais (a Meta exige os dois no `product_list`, e os padrões vêm do
# en.yml). Erro é SEMPRE nomeado (`CustomExceptions::Catalog::*`), para a tela dizer o que falta.
class Catalog::MetaMessageBuilder
  # Teto do `product_list` da Meta.
  LIMITE_DE_ITENS = 30

  # Teto do título de seção da Meta.
  LIMITE_DO_TITULO = 24

  def initialize(conversation:, produtos:, corpo: nil, cabecalho: nil)
    @conversation = conversation
    @produtos = Array(produtos)
    @corpo = corpo.presence || I18n.t('catalog.message.body')
    @cabecalho = cabecalho.presence || I18n.t('catalog.message.header')
  end

  def perform
    validar!
    @produtos.one? ? payload_de_produto : payload_de_lista
  end

  private

  def validar!
    # A WAHA não tem catálogo — nenhum (ver C10, bloqueada por decisão de produto). O erro nomeado
    # é tudo o que cabe aqui.
    raise CustomExceptions::Catalog::ChannelNotSupported, {} unless canal.try(:supports_interactive_payload?)
    raise CustomExceptions::Catalog::CatalogNotConfigured, {} if catalogo_id.blank?
    raise CustomExceptions::Catalog::TooManyProducts, { limit: LIMITE_DE_ITENS, count: @produtos.size } if @produtos.size > LIMITE_DE_ITENS

    @produtos.each { |produto| conferir_espelho(produto) }
  end

  # O estado "ainda não sincronizado". Sem SKU não existe `product_retailer_id`; sem
  # `meta_product_id` o item ainda não foi confirmado do lado da Meta, e a mensagem chegaria vazia
  # ao cliente.
  def conferir_espelho(produto)
    return if produto.sku.present? && produto.meta_product_id.present?

    raise CustomExceptions::Catalog::ProductNotSynced, { product: produto.name }
  end

  def canal
    @canal ||= @conversation.inbox.channel
  end

  def catalogo_id
    @conversation.account.meta_catalog_id
  end

  def payload_de_produto
    {
      type: 'product',
      body: { text: @corpo },
      action: { catalog_id: catalogo_id, product_retailer_id: @produtos.first.sku }
    }
  end

  def payload_de_lista
    {
      type: 'product_list',
      header: { type: 'text', text: @cabecalho },
      body: { text: @corpo },
      action: { catalog_id: catalogo_id, sections: secoes }
    }
  end

  # Uma seção por categoria, que é como o cliente lê a lista. Produto sem categoria cai numa seção
  # genérica em vez de sumir.
  def secoes
    @produtos.group_by { |produto| produto.category&.name.presence || I18n.t('catalog.message.section') }
             .map do |titulo, itens|
      { title: titulo.slice(0, LIMITE_DO_TITULO), product_items: itens.map { |produto| { product_retailer_id: produto.sku } } }
    end
  end
end
