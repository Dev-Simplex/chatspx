# Quando a abertura de uma troca de canal falha na entrega (número sem WhatsApp, por exemplo), o
# status chega depois, pelo webhook, e a ferramenta que levou o cliente já respondeu. Este listener
# devolve a falha à conversa de origem: uma nota para o time e um atributo que a IA de lá lê no
# próximo turno, para pedir a correção ao cliente. O próximo envio bem-sucedido apaga o atributo.
#
# Handler rescue-wrapped: roda para TODA conta no AsyncDispatcher, e uma exceção aqui derrubaria
# os listeners seguintes do EventDispatcherJob.
class Spx::TrocaDeCanalFalhaListener < BaseListener
  def message_updated(event)
    message = event.data[:message]
    return unless falhou_agora?(message, event.data[:previous_changes])

    origem = Conversation.find_by(id: message.additional_attributes[Whatsapp::ContactInviteService::ORIGEM_DA_ABERTURA],
                                  account_id: message.account_id)
    avisar(origem, message) if origem
  rescue StandardError => e
    Rails.logger.error("[Spx::TrocaDeCanalFalhaListener] msg=#{event&.data&.dig(:message)&.id}: #{e.message}")
  end

  private

  def falhou_agora?(message, mudancas)
    message&.failed? && Array(mudancas&.dig('status')).last.to_s == 'failed' &&
      message.additional_attributes&.key?(Whatsapp::ContactInviteService::ORIGEM_DA_ABERTURA)
  end

  def avisar(origem, message)
    canal = message.inbox.name
    motivo = message.external_error.presence
    aviso = "A mensagem de abertura pelo canal #{canal} não foi entregue#{" (#{motivo})" if motivo}. " \
            'Confirme com o cliente o número de WhatsApp, com DDD, antes de tentar de novo.'
    origem.update!(custom_attributes: origem.custom_attributes.merge(Whatsapp::ContactInviteService::FALHA_KEY => aviso))
    origem.messages.create!(account_id: origem.account_id, inbox_id: origem.inbox_id, message_type: :outgoing,
                            private: true, content: aviso)
  end
end
