# frozen_string_literal: true

# Envelope assincrono do Waha::GroupSyncService — usado quando queremos o sync
# fora do ciclo de request (o endpoint de "Sincronizar agora" roda sincrono para
# poder devolver o snapshot na hora).
#
# Sem retry: o servico ja tem circuit breaker por sessao e o snapshot anterior
# continua valendo. Reenfileirar em cima de uma WAHA fora do ar so multiplica
# chamada — foi exatamente o que fez o ResolveLidJob virar 1776 execucoes/dia.
class Waha::GroupSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  discard_on StandardError do |job, error|
    Rails.logger.warn("[WAHA][GroupSyncJob] descartado para conversa #{job.arguments.first}: #{error.class}: #{error.message}")
  end

  def perform(conversation_id, force: false)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Waha::GroupSyncService.new(conversation, force: force).perform
  end
end
