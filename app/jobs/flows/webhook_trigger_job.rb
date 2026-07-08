# frozen_string_literal: true

# Executa a fatia PESADA do gatilho `external_webhook` fora do ciclo HTTP: o
# Webhooks::FlowsController já validou token/engine/cap/rate-limit/dedupe e resolveu o alvo, então
# a resposta 202 volta rápido e o RunnerService (que envia mensagens etc.) roda aqui. Espelha o
# Flows::ExecutionJob (um RunnerService por conversa, erros isolados no tracker).
#
# RE-VALIDA o estado: entre o enqueue e a execução o flow pode ter sido desativado/removido, o
# motor desligado, ou a conversa apagada. Confere tudo de novo antes de disparar — a validação do
# controller é otimista, esta é a última linha.
class Flows::WebhookTriggerJob < ApplicationJob
  queue_as :medium

  def perform(flow_id, conversation_display_id:, payload: {})
    flow = Flow.active.external_webhook.find_by(id: flow_id)
    return if flow.nil?
    return unless flow.account.flows_engine_enabled?

    conversation = flow.account.conversations.find_by(display_id: conversation_display_id)
    return if conversation.nil?

    Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload.to_h).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: flow&.account).capture_exception
  end
end
