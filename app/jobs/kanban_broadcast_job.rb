# frozen_string_literal: true

# Job assíncrono que faz o broadcast real via ActionCable (KANBAN-P1-13).
# Roda na queue `:critical` para latência baixa. Idempotente (apenas envia).
class KanbanBroadcastJob < ApplicationJob
  queue_as :critical

  def perform(stream_name, payload)
    return if stream_name.blank? || payload.blank?

    ActionCable.server.broadcast(stream_name, payload)
  end
end
