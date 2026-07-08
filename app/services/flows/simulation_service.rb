# frozen_string_literal: true

# SIMULAÇÃO (dry-run) de um Flow — a base da Fase 3.3 (o overlay visual no canvas vem numa
# fatia frontend depois). Percorre o grafo com o MESMO walker do disparo real (Flows::
# RunnerService em modo dry_run) seguindo condition/router exatamente como no ar, MAS sem
# efetivar NADA: nenhuma ação é executada (são descritas), `wait` não suspende (é atravessado)
# e nada é gravado — nem FlowStepLog, nem FlowRun, nem a conversa. É 100% INÓCUA POR
# CONSTRUÇÃO: no dry-run o Flows::ActionService (única porta de efeito colateral: mandar
# mensagem, gravar atributo, chamar IA) NEM É INSTANCIADO (ver Flows::RunnerService#walk), e a
# descrição das ações é read-only (Flows::ActionDescriber). Houve um incidente real com
# automação disparando em produção; a simulação é o oposto — não toca no mundo.
#
# ENTRADA / PREMISSAS DA SIMULAÇÃO:
#   • flow          — o Flow a simular (usa flow.definition tal como está, ativo ou não).
#   • conversation  — uma conversa de EXEMPLO, PERSISTIDA e da MESMA conta do flow. As condições
#                     (condition/router) são avaliadas contra o estado ATUAL e REAL dessa
#                     conversa — o motor de condição roda uma query SQL read-only sobre ela — e o
#                     Liquid dos params ({{contact.name}}) é resolvido com os dados dela. Troque a
#                     conversa de exemplo para simular outro cenário. NÃO fabricamos uma conversa
#                     fictícia: o motor de condição precisa de um registro persistido para
#                     consultar (Conversation.where(id: ...)); um contexto puramente sintético
#                     casaria zero condições.
#   • actor / trigger_payload — opcionais, só para paridade de contexto. No dry-run o actor não
#                     muda nada (nenhuma ação roda); o payload alimenta as condições, como no real.
#
# SAÍDA: um Result com `steps` (lista ORDENADA dos nós percorridos — cada um com o que FARIA) e
# `branch_path` (só as decisões de condition/router, na ordem em que foram tomadas).
class Flows::SimulationService
  # Um passo simulado por nó percorrido (formato produzido em Flows::RunnerService#simulate_visit):
  #   action    → { node_id:, type: 'action', action_name:, would:, params_resolved: }
  #   condition → { node_id:, type: 'condition', branch_key: 'true'|'false', would: }
  #   router    → { node_id:, type: 'router', branch_key: <rota casada|fallback>, would: }
  #   wait      → { node_id:, type: 'wait', would: 'aguardaria X', params_resolved: }
  #   trigger/desconhecido → { node_id:, type:, would: 'ponto de passagem (sem efeito)' }
  Result = Struct.new(:steps, :branch_path, keyword_init: true) do
    def to_h
      { steps: steps, branch_path: branch_path }
    end
  end

  def initialize(flow:, conversation:, actor: nil, trigger_payload: {})
    @flow = flow
    @conversation = conversation
    @actor = actor
    @trigger_payload = trigger_payload
  end

  def perform
    runner = Flows::RunnerService.new(
      flow: @flow, conversation: @conversation, actor: @actor, trigger_payload: @trigger_payload
    )
    steps = runner.simulate # dry-run: percorre e descreve; nada é efetivado nem persistido
    Result.new(steps: steps, branch_path: branch_path(steps))
  end

  private

  # O caminho de branches = as decisões dos nós condition/router, na ordem percorrida (cada uma
  # com o ramo escolhido). Deriva dos steps que carregam branch_key.
  def branch_path(steps)
    steps.select { |step| step[:branch_key] }
         .map { |step| { node_id: step[:node_id], type: step[:type], branch: step[:branch_key] } }
  end
end
