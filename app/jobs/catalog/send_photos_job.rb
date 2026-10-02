# frozen_string_literal: true

# O resto do envio de itens do catálogo na conversa: as fotos depois da primeira e o menu da WAHA.
# Uma mensagem por vez, com intervalo — em rajada, a ponte do WhatsApp entrega só a primeira.
class Catalog::SendPhotosJob < ApplicationJob
  queue_as :medium

  INTERVALO = 2

  def perform(conversation, usuario, produto_ids, etapas)
    # Na ordem da primeira mensagem, para o menu numerado bater com a ordem das fotos.
    produtos = conversation.account.catalog_products.where(id: produto_ids).sort_by { |produto| produto_ids.index(produto.id) }
    servico = Catalog::SendProductService.new(conversation: conversation, produtos: produtos, usuario: usuario)

    etapas.each do |etapa|
      sleep(INTERVALO)
      servico.enviar_etapa(etapa)
    end
  end
end
