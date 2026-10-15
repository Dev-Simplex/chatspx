# Motivo de não-entrega de uma mensagem do WhatsApp em linguagem de operador. O mapa vive em
# `campaigns.undelivered.reasons.*` (config/locales) e serve a quem precisa explicar ao time por
# que algo não chegou: a lista de não enviados do disparo (CampaignRecipient) e a abertura do
# lead de formulário (Spx::LeadAberturaFalhaListener).
module Whatsapp::UndeliveredReason
  module_function

  # Falha da Meta grava "131026: Message undeliverable" -> '131026'; falha sem código
  # (exceção interna, erro síncrono da API) -> 'erro_envio'.
  def code(external_error)
    external_error.to_s[/\A\d+/] || 'erro_envio'
  end

  # Código da Meta fora do catálogo cai no grupo (132xxx = template) ou, por último, no texto
  # cru que a Meta mandou.
  def label(code, external_error = nil)
    key = code.match?(/\A\d+\z/) ? "meta_#{code}" : code
    I18n.t("campaigns.undelivered.reasons.#{key}", default: nil) ||
      (code.start_with?('132') && I18n.t('campaigns.undelivered.reasons.template')) ||
      external_error.presence || I18n.t('campaigns.undelivered.reasons.desconhecido')
  end
end
