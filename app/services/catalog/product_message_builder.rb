# frozen_string_literal: true

# Monta a mensagem de item do catálogo que vai para a conversa (C8) e a legenda que o WhatsApp
# mostra: o envio é sempre foto com legenda, em qualquer canal.
#
# A legenda usa a formatação do próprio WhatsApp — *negrito* e ~riscado~ — porque ela É a
# mensagem: não há card nativo, e preço promocional só se lê como promoção se o preço cheio
# aparecer riscado ao lado.
class Catalog::ProductMessageBuilder
  def initialize(produtos)
    @produtos = Array(produtos)
  end

  # O que fica gravado na mensagem para a bolha se reconstruir depois, sem depender do produto
  # continuar existindo nem do preço de hoje: quem abre a conversa em janeiro tem de ver o preço
  # que foi ofertado em setembro.
  def content_attributes
    { catalog_products: @produtos.map { |p| retrato(p) } }
  end

  def legenda
    @produtos.map { |produto| bloco(produto) }.join("\n\n")
  end

  # Menu numerado do fallback WAHA para vários produtos: o álbum de fotos vai junto, mas é o menu
  # que dá ao cliente como responder ("quero o 2").
  def itens_do_menu
    @produtos.map.with_index(1) { |produto, i| { 'title' => ["#{i}. #{produto.name}", preco(produto)].compact.join(' — ') } }
  end

  private

  def retrato(produto)
    {
      'id' => produto.id,
      'sku' => (produto.sku unless sku_escondido?),
      'name' => produto.name,
      'description' => produto.description,
      'price_cents' => produto.price_cents,
      'promo_price_cents' => produto.promo_price_cents,
      'current_price_cents' => produto.preco_atual_cents,
      'currency' => produto.currency,
      'cover_url' => produto.capa_url,
      'category' => produto.category&.name,
      # Já no formato de exibição e sem campo interno: a bolha só desenha, não decide.
      'custom_fields' => campos(produto)
    }
  end

  def bloco(produto)
    linhas = ["*#{produto.name}*", precos(produto)]
    linhas.concat(campos(produto).map { |campo| "#{campo['label']}: #{campo['value']}" })
    linhas << produto.description if produto.description.present?
    linhas << "Cód. #{produto.sku}" if produto.sku.present? && !sku_escondido?
    linhas.compact.join("\n")
  end

  def campos(produto)
    campos_personalizados.para_exibir(produto.custom_attributes)
  end

  # Todos os produtos de um envio são da mesma conta, então as definições são lidas uma vez só.
  def campos_personalizados
    @campos_personalizados ||= Catalog::CustomFields.new(conta)
  end

  def conta
    @produtos.first.account
  end

  def sku_escondido?
    Array(conta.catalog_hidden_fields).include?('sku')
  end

  def precos(produto)
    return preco(produto) unless produto.em_promocao?

    "~#{formatar(produto.price_cents, produto.currency)}~ #{formatar(produto.promo_price_cents, produto.currency)}"
  end

  # Sem preço, não há linha de preço: "R$ 0,00" num imóvel seria informação errada.
  def preco(produto)
    return nil if produto.preco_atual_cents.nil?

    formatar(produto.preco_atual_cents, produto.currency)
  end

  # Sem gem de moeda: são duas linhas e o catálogo é BRL na prática. Outra moeda sai com o código
  # na frente, que é honesto e não inventa símbolo errado.
  def formatar(centavos, moeda)
    valor = format('%.2f', centavos.to_i / 100.0).tr('.', ',')
    inteiro, decimais = valor.split(',')
    inteiro = inteiro.reverse.scan(/\d{1,3}/).join('.').reverse
    moeda.to_s.upcase == 'BRL' ? "R$ #{inteiro},#{decimais}" : "#{moeda} #{inteiro},#{decimais}"
  end
end
