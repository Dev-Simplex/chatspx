# frozen_string_literal: true

# Bloco 5.11 — o leque: um fato registrado vira uma entrega por destino server-side configurado.
#
# A ordem aqui importa e nao e obvia: **primeiro reserva, depois enfileira**. `claim_delivery` grava
# a linha e devolve `nil` quando o indice unico (evento, destino) recusa — e so quem GANHOU a corrida
# enfileira. Enfileirar antes de reservar deixaria dois workers com dois jobs para o mesmo par, e a
# dobra so apareceria na conta do cliente.
#
# Sem credencial (o estado de hoje, enquanto o bloco 5.02 nao aterrissa) nada acontece: nenhuma
# reserva, nenhum job, nenhuma escrita. E o comportamento correto — sem credencial nao ha destino —
# e tambem o que garante que ligar esta trilha nao muda nada nas outras ate 5.02 chegar.
class Tracking::DeliveryDispatcher
  DESTINATIONS = %i[meta_capi ga4_mp google_ads].freeze

  def self.call(event)
    new(event).call
  end

  def initialize(event, settings: nil)
    @event = event
    @settings = settings
  end

  # Devolve os destinos efetivamente enfileirados — e o que o spec conta e o que 5.14 loga.
  def call
    return [] if settings.nil?

    DESTINATIONS.filter_map { |destination| enqueue(destination) }
  end

  private

  attr_reader :event

  def settings
    return @settings if defined?(@settings) && !@settings.nil?

    @settings = Tracking::CredentialResolver.call(account: event.account, inbox: event.inbox)
  end

  def enqueue(destination)
    return nil unless destination_client(destination).configured?

    delivery = event.claim_delivery(destination)
    return nil if delivery.nil?

    job_class(destination).perform_later(delivery.id)
    destination
  end

  def destination_client(destination)
    destination_class(destination).new(event: event, settings: settings)
  end

  def destination_class(destination)
    "Tracking::Destinations::#{destination.to_s.camelize}".constantize
  end

  def job_class(destination)
    "Tracking::#{destination.to_s.camelize}DeliveryJob".constantize
  end
end
