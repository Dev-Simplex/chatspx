# frozen_string_literal: true

# Foto do produto para a META (C9). Fica FORA do namespace autenticado de propósito: quem busca a
# imagem é o crawler da Meta, que não tem sessão nem token de conta.
#
# Serve os bytes em vez de redirecionar para o link do ActiveStorage porque é justamente aquele link
# que expira em 30 minutos em produção — e a Meta faz cache da `image_url`, então o redirecionamento
# só adiaria o problema que esta rota existe para resolver.
class Catalog::PublicImagesController < ApplicationController
  # Um dia: a Meta refaz a busca de vez em quando, e a capa muda pouco.
  CACHE = 1.day

  def show
    produto = CatalogProduct.find_signed(params[:id], purpose: CatalogProduct::IMAGEM_PUBLICA)
    # Produto oculto ou sem foto é 404, e não uma imagem vazia: catálogo da Meta com item quebrado
    # é pior para o cliente final do que item ausente.
    return head :not_found if produto.nil? || !produto.visible? || produto.capa.blank?

    servir(produto.capa)
  end

  # As fotos da galeria (`additional_image_urls`). A assinatura é da própria foto, então foto
  # apagada é 404 sem mexer na URL das outras.
  def extra
    imagem = ActiveStorage::Attachment.find_signed(params[:id], purpose: CatalogProduct::IMAGEM_PUBLICA)
    produto = imagem&.record
    return head :not_found unless produto.is_a?(CatalogProduct) && produto.visible?

    servir(imagem)
  end

  private

  def servir(imagem)
    expires_in CACHE, public: true
    send_data imagem.download, type: imagem.content_type, disposition: 'inline'
  end
end
