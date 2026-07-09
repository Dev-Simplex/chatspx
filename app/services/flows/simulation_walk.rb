# frozen_string_literal: true

# Comportamento do walker (Flows::RunnerService) em modo SIMULAÇÃO (dry_run) — mixin. Reusa o
# grafo/arestas e a AVALIAÇÃO de condições do runner, mas troca "executa ação" por "descreve
# ação" e "suspende no wait" por "registra e segue". NUNCA executa, suspende ou persiste:
#   • condition/router são AVALIADOS de verdade — o motor de condição é read-only (monta SQL e
#     faz `.any?`, ver ConditionsFilterService), então o ramo tomado é IDÊNTICO ao disparo real.
#   • action é DESCRITA (Flows::ActionDescriber, read-only) — nunca executada.
#   • wait NÃO suspende: registra "aguardaria X" e devolve nil; o walker segue pelo sucessor
#     (primeira aresta de saída), percorrendo o caminho INTEIRO em vez de parar.
#   • os passos vivem só em @simulation_steps (memória); nada toca o banco.
# Depende do host Flows::RunnerService: @simulation_steps, @conversation, @flow e os privados
# evaluate_condition, evaluate_router, normalized_wait. Ver Flows::SimulationService.
module Flows::SimulationWalk
  private

  # Percorre UM nó em modo simulação. Devolve o `branch` a seguir (condition/router) ou nil
  # (action/wait/trigger/desconhecido — nós que não ramificam; o walker segue a 1ª aresta).
  def simulate_visit(node)
    case node['type']
    when 'condition' then simulated_branch(node) { evaluate_condition(node) ? 'true' : 'false' }
    when 'router' then simulated_branch(node) { evaluate_router(node) }
    else record_terminal(node)
    end
  end

  # Avalia o ramo (read-only) e registra a decisão tomada, devolvendo a `key` do ramo escolhido.
  def simulated_branch(node)
    branch = yield
    @simulation_steps << { node_id: node['id'], type: node['type'].to_s, branch_key: branch, would: "seguiria o ramo '#{branch}'" }
    branch
  end

  # Nós que NÃO ramificam: registra o passo e devolve nil (o walker segue a 1ª aresta de saída).
  def record_terminal(node)
    case node['type']
    when 'action' then record_simulated_action(node)
    when 'wait' then record_simulated_wait(node)
    else record_simulated_passthrough(node) # trigger / desconhecido: só atravessa (paridade c/ real)
    end
    nil
  end

  # Descreve o que a AÇÃO faria SEM executá-la (Flows::ActionDescriber é read-only: só lê os
  # params e resolve Liquid contra a conversa de exemplo — nunca chama MessageBuilder/update!/IA).
  def record_simulated_action(node)
    described = simulation_describer.describe(node)
    @simulation_steps << {
      node_id: node['id'], type: 'action', action_name: node['action_name'],
      would: described[:would], params_resolved: described[:params_resolved]
    }
  end

  # Registra "aguardaria X" sem suspender nem criar FlowRun (reusa a normalização do disparo real).
  def record_simulated_wait(node)
    w = normalized_wait(node)
    business_hours = ActiveModel::Type::Boolean.new.cast(w[:business_hours])
    @simulation_steps << {
      node_id: node['id'], type: 'wait',
      would: "aguardaria #{w[:value]} #{w[:unit]}#{business_hours ? ' (em horário comercial)' : ''}",
      params_resolved: { 'value' => w[:value], 'unit' => w[:unit], 'business_hours' => business_hours }
    }
  end

  def record_simulated_passthrough(node)
    @simulation_steps << { node_id: node['id'], type: node['type'].to_s, would: 'ponto de passagem (sem efeito)' }
  end

  def simulation_describer
    @simulation_describer ||= Flows::ActionDescriber.new(conversation: @conversation, account: @flow.account)
  end
end
