# Chama o carimbo de origem quando chega mensagem de quem clicou num anúncio.
#
# Fica num listener, e não no pipeline de recebimento, para não tocar o caminho crítico da
# ingestão de mensagem: aqui uma falha atrasa um atributo, lá derrubaria a entrega.
#
# Não é opt-in por conta porque só age quando a Meta manda `referral` — ou seja, apenas em
# conta que de fato roda anúncio de clique-para-WhatsApp — e o que ele grava é fato, não
# comportamento. Se algum cliente não quiser a label, vira um gate de uma linha.
#
# Handler rescue-wrapped: roda para TODA conta no AsyncDispatcher, e uma exceção aqui derrubaria
# os listeners seguintes do EventDispatcherJob (mesmo motivo do FunnelAutomationListener).
class Spx::CtwaVisibilityListener < BaseListener
  def message_created(event)
    message, _account = extract_message_and_account(event)
    return if message.nil? || !message.incoming? || message.private?

    Whatsapp::ReferralVisibilityService.new(message: message).perform
  rescue StandardError => e
    Rails.logger.error("[Spx::CtwaVisibilityListener] msg=#{event&.data&.dig(:message)&.id}: #{e.message}")
  end
end
