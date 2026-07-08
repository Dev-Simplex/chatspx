# frozen_string_literal: true

# Instrumentação do DISPARO REAL do walker (Flows::RunnerService) — mixin. Roda UM nó de ação/ramo,
# mede a duração e grava um FlowStepLog (a trilha de auditoria por passo). SÓ o caminho real passa
# por aqui: no dry-run o walker usa Flows::SimulationWalk e NÃO instrumenta/persiste nada.
#
# Best-effort absoluto: o ActionService NUNCA levanta (devolve um Result) e o INSERT do log é
# capturado — a observabilidade não pode derrubar a execução do flow. Depende do host
# (Flows::RunnerService): @flow, @conversation, @flow_run, @dry_run e os privados
# evaluate_condition/evaluate_router (via os blocos de #instrument_branch, avaliados no host).
module Flows::StepInstrumentation
  private

  # Roda a ação e registra success/failed/skipped. O ActionService é best-effort e NUNCA levanta:
  # devolve um Result que traduzimos em status + error_code/message. Se o retorno não for um Result
  # (ex.: um instance_spy nos testes), tratamos como success.
  def instrument_action(node, actions)
    started = monotonic_ms
    outcome = actions.execute(node)
    outcome = Flows::ActionService::Result.new(:success) unless outcome.is_a?(Flows::ActionService::Result)
    record_step(node, status: outcome.status, error: outcome.error, duration_ms: elapsed_ms(started))
  end

  # Avalia um nó de ramificação (condition/router), grava o branch tomado e o devolve. O bloco
  # calcula o branch: 'true'/'false' para `condition`; a `route.key` que casou (ou o fallback) para
  # `router`. Um erro na avaliação é registrado como failed e RE-LEVANTADO — preserva o
  # comportamento atual (uma avaliação que estoura aborta o passo), com rastro.
  def instrument_branch(node)
    started = monotonic_ms
    branch = yield
    record_step(node, status: :success, branch_key: branch, duration_ms: elapsed_ms(started))
    branch
  rescue StandardError => e
    record_step(node, status: :failed, error: e, duration_ms: elapsed_ms(started))
    raise
  end

  # Grava UM passo. Best-effort absoluto: se o INSERT falhar, capturamos e seguimos — a
  # observabilidade NUNCA pode derrubar a execução do flow. @flow_run é nil enquanto não há
  # suspensão (fluxo linear), então o passo fica sem run, o que é esperado.
  def record_step(node, status:, duration_ms:, error: nil, branch_key: nil)
    # Defense-in-depth: simulação NUNCA persiste. Hoje o dry-run (Flows::SimulationWalk) sequer
    # chega aqui, mas o guard blinda contra uma futura religação do caminho real no dry-run — a
    # inocuidade não pode depender de o chamador lembrar disso.
    return if @dry_run

    FlowStepLog.create!(
      flow: @flow, account: @flow.account, conversation: @conversation, flow_run: @flow_run,
      node_id: node['id'], action_name: node['action_name'],
      status: status, branch_key: branch_key,
      error_code: error && error_code_for(error, node), error_message: error&.message,
      duration_ms: duration_ms, metadata: { 'node_type' => node['type'] }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @flow.account).capture_exception
  end

  # Mapeia a exceção capturada para um código legível e triável. Skips já trazem o código tipado;
  # NoMethodError no dispatch (action_name inexistente — validado no model, mas defensivo aqui)
  # vira 'unknown_action'; o resto cai em famílias conhecidas ou 'generic'.
  def error_code_for(error, node)
    case error
    when Flows::StepSkip then error.code
    when NoMethodError then error.name.to_s == node['action_name'].to_s ? 'unknown_action' : 'generic'
    when ActiveRecord::RecordNotFound then 'record_not_found'
    when ActiveRecord::RecordInvalid then 'record_invalid'
    else 'generic'
    end
  end

  def monotonic_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  end

  def elapsed_ms(started)
    (monotonic_ms - started).round
  end
end
