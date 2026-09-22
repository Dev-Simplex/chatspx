# frozen_string_literal: true

# Põe o produto dentro da conversa (C8) e resolve o formato da caixa (C10).
#
# O produto vai como MENSAGEM COMUM com anexo: é o que faz ele chegar ao cliente em qualquer canal
# sem caminho de envio novo — no WhatsApp vira foto com legenda, no widget vira imagem com texto.
# O que transforma isso num card de produto na tela do atendente é o `content_attributes`, que a
# bolha lê para se reconstruir.
class Catalog::SendProductService
  def initialize(conversation:, produtos:, usuario:)
    @conversa = conversation
    @produtos = produtos
    @usuario = usuario
    @montador = Catalog::ProductMessageBuilder.new(produtos)
  end

  def perform
    mensagem = criar_mensagem
    anexar_fotos(mensagem)
    enviar_menu_numerado if menu_numerado?
    avisar_erp
    mensagem
  end

  private

  def criar_mensagem
    @conversa.messages.create!(
      account_id: @conversa.account_id,
      inbox_id: @conversa.inbox_id,
      message_type: :outgoing,
      sender: @usuario,
      content: @montador.legenda,
      content_attributes: @montador.content_attributes
    )
  end

  # A foto é o MESMO blob do produto, não uma cópia: o catálogo é a fonte, e duplicar arquivo a
  # cada envio encheria o disco com o mesmo JPEG.
  def anexar_fotos(mensagem)
    @produtos.each do |produto|
      next if produto.capa.blank?

      anexo = mensagem.attachments.new(account_id: @conversa.account_id, file_type: :image)
      anexo.file.attach(produto.capa.blob)
      anexo.save!
    end
  end

  # Só na caixa WAHA e só com mais de um produto: é o teto do canal (a WAHA não tem catálogo, ver
  # docs/catalogo-whatsapp.md). Com um produto só, a legenda da foto já diz tudo.
  def menu_numerado?
    @produtos.size > 1 && @conversa.inbox.channel_type == 'Channel::Api' && @conversa.inbox.waha_session_name.present?
  end

  def enviar_menu_numerado
    corpo = I18n.t('catalog.send.menu_header', count: @produtos.size)
    linhas = @montador.itens_do_menu.pluck('title')
    @conversa.messages.create!(
      account_id: @conversa.account_id,
      inbox_id: @conversa.inbox_id,
      message_type: :outgoing,
      sender: @usuario,
      content: [corpo, *linhas].join("\n")
    )
  end

  # Evento da C4: é por ele que o ERP sabe o que o atendimento está ofertando.
  def avisar_erp
    @produtos.each { |produto| produto.avisar_enviado_no_chat(conversation_id: @conversa.display_id) }
  end
end
