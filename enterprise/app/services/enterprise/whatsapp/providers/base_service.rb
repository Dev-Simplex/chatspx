# Rede de segurança da resposta em voz do Captain.
#
# Nota de voz que falha no envio deixa o cliente SEM RESPOSTA NENHUMA — nem áudio, nem texto.
# A `Captain::Tools::ResponderEmAudioTool` instrui o agente a encerrar o turno com `[IGNORAR]`
# assim que ANEXA o áudio, mas o envio é assíncrono (`Message#send_reply` atrasa o job em 2s
# justamente por causa do anexo): quando ele falha, o agente já se calou e não há texto pra cair
# de volta. Foi exatamente assim que um pedido de áudio do cliente ficou sem qualquer resposta
# em 05/08/2026, na conta 6.
#
# O transcript do que seria falado já está no `content` da própria mensagem — a tool grava ali
# para o dashboard e o Eval enxergarem o que foi dito, e no Cloud API o áudio sai sem legenda,
# então esse texto nunca chegou ao cliente. Aqui ele vira mensagem de texto: o cliente recebe a
# resposta, só não recebe em voz.
#
# Fica no overlay Enterprise porque o Captain é Enterprise — o canal OSS não deve conhecer
# `Captain::Assistant`. Sem laço: a mensagem de texto criada não tem anexo, então uma falha dela
# não reentra em `failed_voice_note?`.
module Enterprise::Whatsapp::Providers::BaseService
  def handle_error(response, message)
    super
    deliver_voice_note_transcript(message)
  end

  private

  # Nunca levanta: isto roda DENTRO do tratamento de erro do envio. Explodir aqui trocaria uma
  # falha de áudio por uma exceção no meio do caminho de falha.
  def deliver_voice_note_transcript(message)
    return unless failed_voice_note?(message)

    message.conversation.messages.create!(
      message_type: :outgoing,
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      sender: message.sender,
      content: message.content,
      content_attributes: { 'voice_note_fallback_for' => message.id }
    )
  rescue StandardError => e
    Rails.logger.error("[VoiceNoteFallback] msg #{message&.id}: #{e.class}: #{e.message}")
  end

  def failed_voice_note?(message)
    message&.status == 'failed' &&
      message.sender_type == 'Captain::Assistant' &&
      message.content.present? &&
      message.attachments.any? { |attachment| attachment.file_type == 'audio' }
  end
end
