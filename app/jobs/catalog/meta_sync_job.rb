# frozen_string_literal: true

# Uma passada do espelho da Meta (C9), uma conta por vez. Conta sem `meta_catalog_id` ou sem caixa
# `whatsapp_cloud` termina em silêncio dentro do serviço.
class Catalog::MetaSyncJob < ApplicationJob
  queue_as :low

  # Quando a cota da hora da Meta acaba (429), reagendar é o único tratamento que não a queima de
  # vez: o `retry_on` do ActiveJob voltaria em segundos, tomaria 429 de novo e gastaria as
  # tentativas todas contra o mesmo limite.
  ESPERA_DO_LIMITE = 1.hour

  def perform(account)
    resultado = Catalog::MetaSyncService.new(account).perform
    self.class.set(wait: ESPERA_DO_LIMITE).perform_later(account) if resultado[:limite_atingido]
  end
end
