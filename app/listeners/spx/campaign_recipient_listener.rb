# Leva ao destinatário da campanha o que acontece com o disparo dele: entregue, lido e falhou
# pelo status da mensagem do template; respondeu pela primeira mensagem recebida depois do envio.
# A regra mora em `Campaigns::Whatsapp::RecipientTracker`.
#
# Roda para TODA mensagem da instância, por isso cada handler é uma consulta indexada e o
# rescue protege os listeners seguintes do EventDispatcherJob (ver FunnelAutomationListener).
class Spx::CampaignRecipientListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    Campaigns::Whatsapp::RecipientTracker.reply(message)
  rescue StandardError => e
    Rails.logger.error("[Spx::CampaignRecipientListener] message=#{message&.id}: #{e.message}")
  end

  def message_updated(event)
    message, = extract_message_and_account(event)
    return unless message.outgoing?

    Campaigns::Whatsapp::RecipientTracker.message_status(message)
  rescue StandardError => e
    Rails.logger.error("[Spx::CampaignRecipientListener] message=#{message&.id}: #{e.message}")
  end
end
