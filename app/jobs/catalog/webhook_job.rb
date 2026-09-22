# frozen_string_literal: true

# Entrega dos webhooks do catálogo (C4). Usa o MESMO `Webhooks::Trigger` de todo o resto — é lá
# que mora a regra dura de só reenviar quando o destino comprovadamente não recebeu (500 e timeout
# de leitura NÃO reenviam, porque o destino pode ter processado).
#
# O que muda em relação ao `WebhookJob` comum é só a cadência: o contrato com o ERP promete
# retentativa em 1, 5 e 30 minutos, em vez do intervalo crescente do resto do sistema.
class Catalog::WebhookJob < ApplicationJob
  queue_as :medium

  ESPERAS = [1.minute, 5.minutes, 30.minutes].freeze

  retry_on StandardError, wait: ->(executions) { ESPERAS[executions - 1] || ESPERAS.last },
                          attempts: ESPERAS.size + 1 do |job, error|
    url, payload = job.arguments
    Webhooks::Trigger.new(url, payload, :account_webhook).handle_failure(error)
  end
  discard_on ActiveJob::DeserializationError

  def perform(url, payload, secret: nil, delivery_id: nil)
    Webhooks::Trigger.execute(url, payload, :account_webhook, secret: secret, delivery_id: delivery_id)
  end
end
