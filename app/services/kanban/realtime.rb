# frozen_string_literal: true

# Ponto único de disparo dos eventos de tempo real do Kanban
# (plano task/kanban-tempo-real.md).
#
# Existe por três motivos:
#
# 1. **Invariante do contrato de eventos:** todo dispatch do board é
#    best-effort. Um broadcast quebrado NUNCA pode quebrar a ação do usuário
#    (arrastar, criar, apagar). Em vez de repetir `rescue StandardError` em seis
#    lugares, o rescue mora aqui.
#
# 2. **Kill switch operacional.** O plano previa uma feature flag
#    `kanban_realtime`, mas `accounts.feature_flags` é um bitmask `bigint` (máx
#    63 bits) e este fork já tem 65 entradas em `config/features.yml` — flag nova
#    nasceria no bit 66 e estouraria com `RangeError` ao ser habilitada
#    (código morto). `KANBAN_REALTIME_ENABLED=false` no .env + restart dá a mesma
#    válvula (parar o tráfego novo na fila `:critical` sem rollback de código)
#    sem gastar bit.
#
# 3. **Alcance.** Quem pode receber o evento de um funil é uma regra só, e ela
#    espelha a `FunnelPolicy` — ver `ActionCableListener#funnel_audience_tokens`.
module Kanban::Realtime
  module_function

  def enabled?
    ENV.fetch('KANBAN_REALTIME_ENABLED', 'true').to_s.downcase != 'false'
  end

  # `payload` é o hash de dados do evento (vira `event.data` no listener).
  def dispatch(event_name, payload)
    return unless enabled?

    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, payload)
  rescue StandardError => e
    Rails.logger.warn("Kanban::Realtime broadcast failed (#{event_name}): #{e.class} - #{e.message}")
  end
end
