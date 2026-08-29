# frozen_string_literal: true

# Bloco 4.14 — retencao de 7 dias do log de entregas.
#
# `delete_all` e nao `destroy_all`: sao milhares de linhas por conta e nao ha callback a
# rodar. Em lotes para nao segurar a tabela num unico DELETE gigante.
class Webhooks::DeliveryCleanupJob < ApplicationJob
  # Agendado diariamente as 03:20 UTC em config/schedule.yml. A fila tem de ser a MESMA da
  # entrada de la: sidekiq-cron 2.4.0 (job.rb:174) enfileira com `set(queue: ...)` usando a
  # fila do schedule, entao um `queue_as` divergente aqui seria uma declaracao que mente
  # sobre onde o job roda. O spec do agendamento trava as duas pontas juntas.
  queue_as :scheduled_jobs
  BATCH = 5_000

  def perform
    loop do
      apagadas = WebhookDelivery.where(id: WebhookDelivery.expired.limit(BATCH).select(:id)).delete_all
      break if apagadas.zero?
    end
  end
end
