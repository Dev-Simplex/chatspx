# frozen_string_literal: true

# Mensagem NATIVA de catálogo do WhatsApp oficial: `product` para um item, `product_list` para
# vários. Só monta — quem envia é o `WhatsappCloudService#send_raw_interactive`, que já manda
# qualquer `content_attributes['interactive_payload']`.
#
# A Meta só envia item que mora no catálogo dela (C9). Quando não dá — outro canal, conta sem
# catálogo, item ainda não espelhado —, `disponivel?` diz não e o envio cai na foto com legenda,
# que chega em qualquer canal. Nada de erro: o atendente quer o item na conversa, não um motivo.
class Catalog::MetaMessageBuilder
  # Tetos do `product_list` da Meta.
  LIMITE_DE_ITENS = 30
  LIMITE_DE_SECOES = 10
  LIMITE_DO_TITULO = 24

  def initialize(conversation:, produtos:)
    @conversation = conversation
    @produtos = Array(produtos)
  end

  def disponivel?
    @conversation.inbox.channel.supports_interactive_payload? &&
      catalogo_id.present? &&
      @produtos.size <= LIMITE_DE_ITENS &&
      secoes.size <= LIMITE_DE_SECOES &&
      @produtos.all? { |produto| espelhado?(produto) }
  end

  def perform
    @produtos.one? ? payload_de_produto : payload_de_lista
  end

  private

  # Sem `meta_product_id` a Meta ainda não confirmou o item, e a mensagem chegaria vazia ao cliente.
  def espelhado?(produto)
    produto.visible && produto.sku.present? && produto.meta_product_id.present?
  end

  def catalogo_id
    @conversation.account.meta_catalog_id
  end

  def payload_de_produto
    {
      'type' => 'product',
      'body' => { 'text' => I18n.t('catalog.message.body') },
      'action' => { 'catalog_id' => catalogo_id, 'product_retailer_id' => @produtos.first.sku }
    }
  end

  def payload_de_lista
    {
      'type' => 'product_list',
      'header' => { 'type' => 'text', 'text' => I18n.t('catalog.message.header') },
      'body' => { 'text' => I18n.t('catalog.message.body') },
      'action' => { 'catalog_id' => catalogo_id, 'sections' => secoes }
    }
  end

  # Uma seção por categoria, que é como o cliente lê a lista. Item sem categoria cai numa seção
  # genérica em vez de sumir.
  def secoes
    @secoes ||= @produtos.group_by { |produto| produto.category&.name.presence || I18n.t('catalog.message.section') }
                         .map do |titulo, itens|
      { 'title' => titulo.slice(0, LIMITE_DO_TITULO), 'product_items' => itens.map { |produto| { 'product_retailer_id' => produto.sku } } }
    end
  end
end
