# frozen_string_literal: true

# O destino esta fora do ar ou pediu calma (5xx, 429, 408, falha de rede). Vai para o backoff.
class Tracking::DeliveryError::Retryable < Tracking::DeliveryError; end
