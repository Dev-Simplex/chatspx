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
    @removidos = 0
    @pulados = []
  end

  def perform
    return resultado unless configurado?

    remover_ocultos
    produtos.each_slice(TAMANHO_DO_LOTE) { |lote| sincronizar_lote(lote) }
    resultado
  rescue CustomExceptions::Catalog::MetaRateLimited
    # A cota da hora acabou. A passada PARA aqui e quem chamou reagenda; insistir agora só gastaria
    # tentativa contra o mesmo limite, e o que já foi carimbado não volta na próxima varredura.
    resultado(limite_atingido: true)
  end

  # Pública porque a aba decide por ela se mostra selo e botão de sincronizar: conta sem espelho
  # veria todo produto "pendente" para sempre.
  def configurado?
    catalogo_id.present? && canal.present?
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

  # Só produto visível: o invisível não entra na vitrine da Meta, e quem já entrou sai por
  # `remover_ocultos`.
  def produtos
    @account.catalog_products.visiveis.para_sincronizar.order(:id).limit(LIMITE_DA_PASSADA)
  end

  # Produto que some da vitrine tem que sumir do catálogo da Meta também. Sem isto o painel diz
  # "oculto" e o cliente final continua vendo o item e podendo comprar — e desativar É remoção: é o
  # que o DELETE da C3 faz e o que o `produto.removido` do model avisa ao ERP.
  #
  # Não filtra por `para_sincronizar`: quem sai leva o `meta_product_id` limpo no mesmo passo, e é
  # isso que o tira desta lista para sempre.
  def ocultos_espelhados
    @account.catalog_products.where(visible: false).where.not(meta_product_id: nil).order(:id).limit(LIMITE_DA_PASSADA)
  end

  def remover_ocultos
    ocultos_espelhados.each_slice(TAMANHO_DO_LOTE) do |lote|
      # Mesma chamada do espelho, outro verbo: o `items_batch` aceita DELETE pela `retailer_id`.
      cliente.catalog_items_batch(catalogo_id, lote.map { |produto| { method: 'DELETE', data: { retailer_id: produto.sku } } })
      lote.each(&:desmarcar_sincronizado!)
      @removidos += lote.size
    end
  end

  def sincronizar_lote(lote)
    enviaveis = lote.select { |produto| enviavel?(produto) }
    return if enviaveis.empty?

    cliente.catalog_items_batch(catalogo_id, enviaveis.map { |produto| { method: 'UPDATE', data: dados(produto) } })
    @enviados += enviaveis.size
    carimbar(enviaveis)
  end

  # A Meta exige do PRODUCT_ITEM a chave do varejista (`retailer_id`, que é o SKU) e a imagem. Item
  # sem um dos dois ela REJEITA, e item rejeitado nunca é carimbado: voltaria em `para_sincronizar`
  # a cada passada, queimando para sempre a mesma cota que o lote existe para poupar.
  # A régua mora no model (`faltas_para_meta`) porque o selo da aba usa a mesma.
  def enviavel?(produto)
    faltas = produto.faltas_para_meta
    return true if faltas.empty?

    # Pular com o motivo registrado é o que mantém o resto do lote de pé: derrubar a chamada por um
    # cadastro incompleto deixaria o catálogo inteiro sem espelho.
    pular(produto, :"sem_#{faltas.first}")
    false
  end

  def pular(produto, motivo)
    @pulados << { id: produto.id, motivo: motivo }
    Rails.logger.info("[catalogo] produto #{produto.id} fora do espelho da Meta: #{motivo}")
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
    { enviados: @enviados, carimbados: @carimbados, removidos: @removidos, pulados: @pulados, limite_atingido: limite_atingido }
  end
end
