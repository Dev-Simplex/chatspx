# frozen_string_literal: true

# Espelho do catálogo na Meta (C9). O banco daqui é a FONTE; o catálogo da Meta é a cópia — e a
# cópia existe porque a Meta só envia produto que mora nela (`catalog_id` + `product_retailer_id`).
# Não existe mandar produto que só está no nosso banco.
#
# UM catálogo por conta (`account.meta_catalog_id`). Conta sem catálogo, ou sem caixa
# `whatsapp_cloud` de onde tirar o token, encerra EM SILÊNCIO: é conta que não ligou o recurso, e
# não defeito para alertar.
class Catalog::MetaSyncService
  # Produtos por chamada. O que importa é não mandar um produto por chamada: 200 produtos assim
  # sozinhos já estourariam a cota de `200 + 40 × catálogos` por hora da Meta.
  TAMANHO_DO_LOTE = 50

  # Teto da passada. Cada lote gasta 2 chamadas (envio + confirmação), então 500 produtos são 20
  # chamadas — folgado dentro da cota. O que sobrar continua em `para_sincronizar` e volta depois.
  LIMITE_DA_PASSADA = 500

  def initialize(account)
    @account = account
    @enviados = 0
    @carimbados = 0
    @pulados = []
  end

  def perform
    return resultado if catalogo_id.blank? || canal.blank?

    produtos.each_slice(TAMANHO_DO_LOTE) { |lote| sincronizar_lote(lote) }
    resultado
  rescue CustomExceptions::Catalog::MetaRateLimited
    # A cota da hora acabou. A passada PARA aqui e quem chamou reagenda; insistir agora só gastaria
    # tentativa contra o mesmo limite, e o que já foi carimbado não volta na próxima varredura.
    resultado(limite_atingido: true)
  end

  private

  def catalogo_id
    @account.meta_catalog_id
  end

  def canal
    @canal ||= @account.whatsapp_channels.find_by(provider: 'whatsapp_cloud')
  end

  def cliente
    @cliente ||= Whatsapp::FacebookApiClient.new(canal.provider_config['api_key'])
  end

  # Só produto visível: o invisível está fora da vitrine, e a rota pública da foto devolve 404 para
  # ele — mandá-lo à Meta criaria item sem imagem lá.
  def produtos
    @account.catalog_products.visiveis.para_sincronizar.order(:id).limit(LIMITE_DA_PASSADA)
  end

  def sincronizar_lote(lote)
    com_sku, sem_sku = lote.partition { |produto| produto.sku.present? }
    sem_sku.each { |produto| pular(produto) }
    return if com_sku.empty?

    cliente.catalog_items_batch(catalogo_id, com_sku.map { |produto| { method: 'UPDATE', data: dados(produto) } })
    @enviados += com_sku.size
    carimbar(com_sku)
  end

  # `retailer_id` é o SKU, e a Meta não aceita item sem a chave do varejista. Produto sem SKU é
  # pulado com o motivo registrado — derrubar o lote por causa dele deixaria o catálogo inteiro sem
  # espelho por um cadastro incompleto.
  def pular(produto)
    @pulados << { id: produto.id, motivo: :sem_sku }
    Rails.logger.info("[catalogo] produto #{produto.id} fora do espelho da Meta: sem SKU")
  end

  # O `items_batch` responde `handles`, não o id do item: quem diz o `meta_product_id` é a consulta
  # ao catálogo. Produto que ainda não apareceu do lado da Meta fica SEM carimbo e volta em
  # `para_sincronizar` na próxima passada — id inventado aqui quebraria o envio lá na frente.
  def carimbar(lote)
    por_sku = lote.index_by(&:sku)
    resposta = cliente.catalog_items(catalogo_id, por_sku.keys)

    Array(resposta['data']).each do |item|
      produto = por_sku[item['retailer_id']]
      next if produto.nil?

      produto.marcar_sincronizado!(item['id'])
      @carimbados += 1
    end
  end

  def dados(produto)
    campos = {
      retailer_id: produto.sku,
      name: produto.name,
      description: produto.description.presence || produto.name,
      # Preço em CENTAVOS, que é o que o `items_batch` espera junto do `currency`.
      price: produto.price_cents,
      currency: produto.currency,
      availability: disponibilidade(produto),
      condition: 'new',
      image_url: produto.public_image_url
    }
    # Promoção tem campo próprio na Meta. Baixar o `price` mostraria o promocional como se fosse o
    # cheio, sem o risco cortado que faz a promoção vender.
    campos[:sale_price] = produto.preco_atual_cents if produto.em_promocao?
    campos
  end

  # `stock` nulo é "não controlo estoque", não "acabou": tratar como esgotado sumiria com a vitrine
  # inteira de quem cadastra produto sem estoque.
  def disponibilidade(produto)
    produto.stock&.zero? ? 'out of stock' : 'in stock'
  end

  def resultado(limite_atingido: false)
    { enviados: @enviados, carimbados: @carimbados, pulados: @pulados, limite_atingido: limite_atingido }
  end
end
