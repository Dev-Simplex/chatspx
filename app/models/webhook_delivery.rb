# frozen_string_literal: true

# Bloco 4.14 — o registro de uma tentativa de entrega.
#
# DE ONDE VEM O STATUS, e por que isso importa: ate o bloco 1.13, a excecao morria dentro
# de Webhooks::Trigger e o job terminava com sucesso — o webhook REPORTAVA entrega que nao
# aconteceu. Um log alimentado por "o job nao explodiu" herdaria exatamente essa mentira.
#
# Por isso quem grava aqui e o proprio Trigger, nos dois pontos em que ele SABE o
# resultado: depois de perform_request voltar sem levantar (entregue) e dentro do rescue,
# com o erro em maos (falhou). Nao existe caminho que grave "entregue" por ausencia de
# excecao em outra camada.
class WebhookDelivery < ApplicationRecord
  RETENTION = 7.days

  belongs_to :webhook
  belongs_to :account

  enum status: { pending: 0, delivered: 1, failed: 2 }

  validates :delivery_id, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # O reenvio reusa o MESMO delivery_id: e ele que permite ao destino deduplicar. Gerar id
  # novo no replay transformaria "a mesma entrega, de novo" em "uma entrega diferente", e o
  # destino processaria duas vezes.
  def replay!
    WebhookJob.perform_later(webhook.url, payload.deep_symbolize_keys, :account_webhook,
                             secret: webhook.secret,
                             delivery_id: delivery_id,
                             webhook_id: webhook_id)
    increment!(:attempts) # rubocop:disable Rails/SkipsModelValidations
    self
  end
end
