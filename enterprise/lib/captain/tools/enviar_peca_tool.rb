# Envia UMA peça do inventário de apresentação do produto, pelo id que a listar_pecas devolveu.
# Genérica e multi-tenant: nada de peça hardcodada — o que existe vem do banco.
class Captain::Tools::EnviarPecaTool < Captain::Tools::BasePublicTool
  include Captain::Tools::ProdutoApresentacao

  # Tipos que viram anexo de mensagem. Peça declarada com tipo fora daqui é recusada com aviso
  # explícito em vez de falhar calada na frente do cliente.
  TIPOS = { 'audio' => :audio, 'imagem' => :image, 'video' => :video, 'documento' => :file }.freeze
  PADRAO = { audio: 'audio/ogg', image: 'image/jpeg', video: 'video/mp4', file: 'application/pdf' }.freeze
  MAX_BYTES = 15 * 1024 * 1024

  description 'Envia ao cliente UMA peça do material de apoio, pelo id devolvido por listar_pecas.'
  param :peca_id, type: 'string',
                  desc: 'O id exato de uma peça que a listar_pecas devolveu nesta conversa. ' \
                        'Não invente id e não envie peça que não esteja naquela lista.',
                  required: true

  def perform(tool_context, peca_id:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    peca = produto_do_lead(conversation)&.peca(peca_id)
    return 'Esse id não está no material disponível. Chame listar_pecas e use um id de lá.' if peca.nil?

    file_type = TIPOS[peca['tipo'].to_s.downcase]
    return "Peça do tipo #{peca['tipo']} ainda não pode ser enviada por aqui." if file_type.nil?
    # Peça catalogada sem material resolvível: aparece na lista (a descrição já ajuda a IA a
    # falar sobre ela), mas não há bytes pra mandar. Recusa explícita em vez de erro no cliente.
    return 'Essa peça está catalogada mas ainda não tem material anexado.' if peca['url'].blank?

    enviar(conversation, peca, file_type)
    'Peça enviada.'
  rescue StandardError => e
    Rails.logger.warn("[EnviarPecaTool] #{e.class}: #{e.message}")
    'Não consegui enviar essa peça agora.'
  end

  private

  def enviar(conversation, peca, file_type)
    io = Down.download(peca['url'], max_size: MAX_BYTES)
    # Anexo construído ANTES do save: o envio dispara no after_create_commit da mensagem, então
    # criar o anexo depois é corrida — o WhatsApp Cloud recebe o payload sem a mídia.
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      additional_attributes: { 'peca_id' => peca['id'] }
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: file_type,
      file: { io: io, filename: nome_arquivo(peca, file_type), content_type: content_type(io, file_type) }
    )
    msg.save!
  end

  def content_type(io, file_type)
    (io.respond_to?(:content_type) && io.content_type.presence) || PADRAO[file_type]
  end

  def nome_arquivo(peca, file_type)
    base = File.basename(URI.parse(peca['url'].to_s).path.to_s)
    base.presence&.match?(/\.\w+\z/) ? base : "#{peca['id']}.#{PADRAO[file_type].split('/').last}"
  end
end
