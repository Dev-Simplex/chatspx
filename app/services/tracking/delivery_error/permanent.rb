# frozen_string_literal: true

# O destino recusou o que mandamos (4xx que nao 429). Repetir devolve a mesma resposta: DLQ direto.
class Tracking::DeliveryError::Permanent < Tracking::DeliveryError; end
