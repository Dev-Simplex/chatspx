# frozen_string_literal: true

# Bloco 5.11 — o molde da fila de entrega server-side: backoff, teto de tentativas e DLQ.
#
# Tres decisoes que sao o bloco inteiro:
#
# 1. **Backoff, nunca laco.** As esperas sao 30 s, 2 min, 10 min, 1 h. Retentar de imediato contra
#    um destino que respondeu 429 e a maneira mais rapida de trocar uma indisponibilidade curta por
#    um bloqueio longo — e a de gastar as cinco tentativas em quinze segundos, quando o destino
#    voltaria em dois minutos.
#
# 2. **A DLQ e uma LINHA DE BANCO, nao uma mensagem de log.** `TrackingDelivery` com `status: dead`
#    guarda destino, status HTTP, codigo e mensagem — o painel de 5.14 lista, o suporte responde
#    "o evento saiu?" sem abrir console de ninguem, e o reenvio tem de onde partir. Log de erro num
#    arquivo e um evento perdido com testemunha.
#
# 3. **Erro permanente nao vai para o backoff.** 4xx que nao 429 (token invalido, pixel que nao
#    existe) morre na primeira tentativa: repetir cinco vezes so atrasa em uma hora a mesma resposta
#    e disfarca de "instabilidade" o que e credencial errada.
#
# A excecao SOBE de proposito (`raise` depois de marcar `failed`). Enquanto `Webhooks::Trigger`
# engolia a dela, o `retry_on` do `webhook_job.rb` nunca via nada e o painel dizia que entregou —
# esta base ja pagou por essa licao uma vez.
class Tracking::DeliveryJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 5
  BACKOFF = [30.seconds, 2.minutes, 10.minutes, 1.hour].freeze

  retry_on Tracking::DeliveryError::Retryable,
           wait: ->(executions) { Tracking::DeliveryJob.backoff_for(executions) },
           attempts: MAX_ATTEMPTS do |job, error|
    job.move_to_dead_letter(error)
  end

  discard_on ActiveJob::DeserializationError

  # A espera da tentativa `executions` (1 = a primeira falha). Estritamente crescente e sempre > 0:
  # e o que separa "backoff" de "laco".
  def self.backoff_for(executions)
    index = [executions.to_i - 1, 0].max
    BACKOFF[[index, BACKOFF.length - 1].min]
  end

  def perform(delivery_id)
    @delivery = TrackingDelivery.find_by(id: delivery_id)
    # Entrega apagada com o evento, ou ja concluida por outra tentativa: nao ha o que fazer.
    return if delivery.nil? || delivery.sent? || delivery.dead?

    deliver
  rescue Tracking::DeliveryError::Permanent => e
    mark_dead(e)
  rescue Tracking::DeliveryError::Retryable => e
    mark_failed(e)
    raise
  end

  # Chamado UMA vez, no esgotamento das tentativas — nunca a cada falha, senao a entrega nasceria
  # morta na primeira tentativa com quatro reentregas ainda por vir (molde: `WebhookJob`).
  def move_to_dead_letter(error)
    @delivery ||= TrackingDelivery.find_by(id: arguments.first)
    return if delivery.nil?

    mark_dead(error)
  end

  # Sobrescrito por cada job de destino.
  def destination_class
    raise NotImplementedError
  end

  private

  attr_reader :delivery

  def deliver
    reason = Tracking::DedupWindow.skip_reason(event)
    return mark_skipped(reason) if reason.present?

    destination = build_destination
    return mark_skipped('not_configured') unless destination.configured?

    register_attempt
    apply(destination.deliver!)
  end

  def event
    delivery.tracking_event
  end

  def build_destination
    destination_class.new(event: event, settings: settings, http_client: http_client)
  end

  # A credencial e resolvida por conta/inbox do EVENTO, nao por parametro do job: job enfileirado
  # carrega id, nunca segredo — segredo em fila e segredo em backup de fila (RC10).
  def settings
    Tracking::CredentialResolver.call(account: event.account, inbox: event.inbox)
  end

  # Ponto de injecao do cliente HTTP. `nil` deixa o destino usar o padrao; o spec troca por um duble.
  def http_client
    nil
  end

  def register_attempt
    delivery.update!(attempts: delivery.attempts + 1, last_attempted_at: Time.current)
  end

  def apply(result)
    return mark_skipped(result.reason) if result.status == :skipped

    delivery.update!(status: :sent, http_status: result.http_status, delivered_at: Time.current,
                     field_names: result.field_names, suppressed_field_names: result.suppressed_field_names,
                     emq: result.emq, error_code: nil, error_message: nil)
  end

  def mark_skipped(reason)
    delivery.update!(status: :skipped, error_code: reason)
  end

  def mark_failed(error)
    delivery.update!(status: :failed, http_status: error.http_status, error_code: error.code,
                     error_message: error.message.to_s[0, 1000])
  end

  def mark_dead(error)
    delivery.update!(status: :dead, http_status: error.try(:http_status), error_code: error.try(:code) || 'exhausted',
                     error_message: error.message.to_s[0, 1000])
  end
end
