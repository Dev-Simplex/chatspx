# frozen_string_literal: true

# Comportamento do nó `wait_for_reply` no walker (Flows::RunnerService) — mixin (F2). Suspende o
# passo ESPERANDO a resposta do contato e, na retomada, RAMIFICA pela opção escolhida (o id da reply
# == o value da opção do send_interactive == edge.branch) ou por 'timeout' (retomada por tempo).
# Extraído p/ manter o RunnerService enxuto (mesmo padrão de Flows::StepInstrumentation/SimulationWalk).
# Depende do host (Flows::RunnerService): as ivars @resume_start_id/@resume_reply e os privados
# persist_suspension e normalize_wait_config. Ver plano/F2-contrato-wait-for-reply.md §AGENTE B.
module Flows::ReplyWait
  private

  # Ao chegar num nó `wait_for_reply`: no 1º toque (walk pra frente, node_id != @resume_start_id)
  # SUSPENDE gravando o PRÓPRIO nó em current_node_id — é ele que a ReplyResumeService (resposta) ou
  # a ResumeService (timeout) reentram. wait_until = prazo do timeout OU nil (espera indefinida pela
  # resposta). Na RETOMADA (node_id == @resume_start_id) devolve false: NÃO suspende, deixa o
  # step_node cair no #visit pra ramificar. Diferente do `wait`, que grava o SUCESSOR e não é
  # reentrado no mesmo nó.
  def suspend_on_wait_for_reply(node, node_id)
    return false unless node['type'] == 'wait_for_reply'
    return false if node_id == @resume_start_id

    persist_suspension(node_id: node_id, wait_until: reply_timeout_until(node))
    true
  end

  # Ramifica um wait_for_reply na RETOMADA. Com resposta (retomada por MENSAGEM — a ReplyResumeService
  # injetou @resume_reply = { id, title }) o id da opção escolhida vira o branch: next_node_id casa
  # `edge.branch == id`; sem aresta correspondente cai na aresta sem rótulo (fallback). SEM resposta
  # (retomada por TEMPO — timeout via ResumeService/ResumeJob, @resume_reply nil) → 'timeout'.
  def evaluate_reply_branch(_node)
    return 'timeout' if @resume_reply.blank?

    @resume_reply['id'].to_s
  end

  # Prazo do timeout: node['timeout'] = { enabled, value, unit }. Desabilitado (ou ausente) → nil = o
  # run espera indefinidamente pela resposta (wait_until nil não entra em FlowRun.due, então o
  # ResumeJob nunca o retoma por tempo). Habilitado → `value.unit.from_now` (reusa a normalização do
  # wait). Sem business_hours — o timeout de resposta é um prazo simples.
  def reply_timeout_until(node)
    timeout = timeout_config(node)
    return nil unless ActiveModel::Type::Boolean.new.cast(timeout['enabled'])

    w = normalize_wait_config(timeout)
    w[:value].public_send(w[:unit]).from_now
  end

  def timeout_config(node)
    raw = node['timeout']
    raw = raw.first if raw.is_a?(Array)
    (raw || {}).to_h.with_indifferent_access
  end
end
