# frozen_string_literal: true

# Põe o produto dentro da conversa (C8) e resolve o formato da caixa (C10).
#
# Dois caminhos:
#
# - **Catálogo nativo** (WhatsApp oficial, item já espelhado na Meta): UMA mensagem `product` ou
#   `product_list`. As fotos vão pela galeria do item na Meta.
# - **Foto com legenda** (WAHA, que não tem catálogo, e qualquer outro caso): por item, a capa com a
#   legenda (nome, preço, campos) e depois as outras fotos soltas. Cada foto é uma mensagem, porque
#   os dois canais do WhatsApp só entregam o PRIMEIRO anexo de cada mensagem.
#
# A primeira mensagem sai na hora; o resto vai pelo `Catalog::SendPhotosJob`, com intervalo — em
# rajada, a ponte do WhatsApp entrega só a primeira (lição da `EnviarFotosImovelTool`).
#
# O que transforma a mensagem num card na tela do atendente é o `content_attributes`, que a bolha
# lê para se reconstruir.
class Catalog::SendProductService
  def initialize(conversation:, produtos:, usuario:)
    @conversa = conversation
    @produtos = produtos
    @usuario = usuario
  end

  def perform
    mensagem = nativo.disponivel? ? enviar_nativo : enviar_fotos
    avisar_erp
    mensagem
  end

  # Público porque é o job quem manda as etapas depois da primeira.
  def enviar_etapa(etapa)
    etapa['menu'] ? enviar_menu_numerado : enviar_foto(etapa)
  end

  private

  def nativo
    @nativo ||= Catalog::MetaMessageBuilder.new(conversation: @conversa, produtos: @produtos)
  end

  def enviar_nativo
    montador = Catalog::ProductMessageBuilder.new(@produtos)
    criar_mensagem(content: montador.legenda,
                   content_attributes: montador.content_attributes.merge('interactive_payload' => nativo.perform))
  end

  def enviar_fotos
    primeira, *resto = etapas
    mensagem = enviar_etapa(primeira)
    Catalog::SendPhotosJob.perform_later(@conversa, @usuario, @produtos.map(&:id), resto) if resto.any?
    mensagem
  end

  # A ordem da conversa: por item, a capa com a legenda e as outras fotos; no fim, o menu da WAHA.
  # Item sem foto vira uma etapa só, com a legenda em texto.
  def etapas
    lista = @produtos.flat_map do |produto|
      fotos = produto.fotos_para_envio
      next [{ 'produto_id' => produto.id, 'legenda' => true }] if fotos.empty?

      fotos.each_with_index.map { |foto, i| { 'produto_id' => produto.id, 'foto_id' => foto.id, 'legenda' => i.zero? } }
    end
    menu_numerado? ? lista + [{ 'menu' => true }] : lista
  end

  def enviar_foto(etapa)
    produto = @produtos.find { |item| item.id == etapa['produto_id'] }
    return if produto.nil?

    mensagem = @conversa.messages.new(atributos_da_mensagem(etapa['legenda'] ? legendado(produto) : {}))
    foto = produto.images.find_by(id: etapa['foto_id']) if etapa['foto_id']
    # A foto é o MESMO blob do produto, não uma cópia: o catálogo é a fonte, e duplicar arquivo a
    # cada envio encheria o disco com o mesmo JPEG. Vai no mesmo `save!` da mensagem para já estar
    # no evento de criação, que é o que a ponte da WAHA lê.
    mensagem.attachments.new(account_id: @conversa.account_id, file_type: :image, file: foto.blob) if foto
    mensagem.save!
    mensagem
  end

  def legendado(produto)
    montador = Catalog::ProductMessageBuilder.new(produto)
    { content: montador.legenda, content_attributes: montador.content_attributes }
  end

  # Só na caixa WAHA e só com mais de um produto: é o teto do canal (a WAHA não tem catálogo, ver
  # docs/catalogo-whatsapp.md). Com um produto só, a legenda da foto já diz tudo.
  def menu_numerado?
    @produtos.size > 1 && @conversa.inbox.channel_type == 'Channel::Api' && @conversa.inbox.waha_session_name.present?
  end

  def enviar_menu_numerado
    corpo = I18n.t('catalog.send.menu_header', count: @produtos.size)
    linhas = Catalog::ProductMessageBuilder.new(@produtos).itens_do_menu.pluck('title')
    criar_mensagem(content: [corpo, *linhas].join("\n"))
  end

  def criar_mensagem(atributos)
    @conversa.messages.create!(atributos_da_mensagem(atributos))
  end

  def atributos_da_mensagem(atributos)
    { account_id: @conversa.account_id, inbox_id: @conversa.inbox_id, message_type: :outgoing, sender: @usuario }.merge(atributos)
  end

  # Evento da C4: é por ele que o ERP sabe o que o atendimento está ofertando.
  def avisar_erp
    @produtos.each { |produto| produto.avisar_enviado_no_chat(conversation_id: @conversa.display_id) }
  end
end
