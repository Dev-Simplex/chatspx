# frozen_string_literal: true

# Bloco 5.11 — entrega ao destino Ga4Mp. Toda a politica (backoff, DLQ, guarda de janela) vem do
# molde; aqui fica so QUAL destino, que e a unica coisa que difere entre os tres.
class Tracking::Ga4MpDeliveryJob < Tracking::DeliveryJob
  def destination_class
    Tracking::Destinations::Ga4Mp
  end
end
