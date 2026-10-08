# A abertura do lead de formulário (Meta::LeadAds::CreateConversationService) sai como template e
# a Meta só diz que falhou depois, pelo webhook de status. Sem isto, a linha de atividade do lead
# dizia "abertura enviada" e o time não ficava sabendo que o cliente não recebeu nada. Este
# listener acrescenta à conversa uma atividade com o motivo, no mapa de motivos do disparo
# (Whatsapp::UndeliveredReason).
#
# Handler rescue-wrapped: roda para TODA mensagem da instância no AsyncDispatcher, e uma exceção
# aqui derrubaria os listeners seguintes do EventDispatcherJob.
class Spx::LeadAberturaFalhaListener < BaseListener
  def message_updated(event)
    message = event.data[:message]
    return unless falhou_agora?(message, event.data[:previous_changes])

    conversation = message.conversation
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                  message_type: :activity, content: aviso(message))
  rescue StandardError => e
    Rails.logger.error("[Spx::LeadAberturaFalhaListener] msg=#{event&.data&.dig(:message)&.id}: #{e.message}")
  end

  private

  def falhou_agora?(message, mudancas)
    message&.failed? && Array(mudancas&.dig('status')).last.to_s == 'failed' &&
      ActiveModel::Type::Boolean.new.cast((message.content_attributes || {})['meta_lead_ads_initial'])
  end

  def aviso(message)
    I18n.with_locale(message.account.locale) do
      code = Whatsapp::UndeliveredReason.code(message.external_error)
      reason = Whatsapp::UndeliveredReason.label(code, message.external_error)
      # Sem código da Meta o rótulo é genérico: o detalhe (ex.: template inexistente) é o que
      # diz ao time o que corrigir.
      reason = "#{reason}: #{message.external_error}" if code == 'erro_envio' && message.external_error.present?
      I18n.t('conversations.activity.lead.opening_failed', reason: reason)
    end
  end
end
