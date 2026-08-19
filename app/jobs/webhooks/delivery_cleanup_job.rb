# frozen_string_literal: true

# Bloco 4.14 — retencao de 7 dias do log de entregas.
#
# `delete_all` e nao `destroy_all`: sao milhares de linhas por conta e nao ha callback a
# rodar. Em lotes para nao segurar a tabela num unico DELETE gigante.
class Webhooks::DeliveryCleanupJob < ApplicationJob
  queue_as :low
  BATCH = 5_000

  def perform
    loop do
      apagadas = WebhookDelivery.where(id: WebhookDelivery.expired.limit(BATCH).select(:id)).delete_all
      break if apagadas.zero?
    end
  end
end
