# frozen_string_literal: true

# Percorre o grafo do Flow (nodes+edges) reusando o ActionService inteiro. Na Fase 1 o
# grafo é LINEAR e SÍNCRONO — sem wait/scheduler (isso é F2): começa na raiz e caminha
# nó a nó seguindo as arestas até acabar. Nós `action` executam; `condition`/`router`
# avaliam e escolhem o ramo; `wait` chega na F2. Guardas: MAX_STEPS (ciclo no grafo por
# aresta malformada) e MAX_DEPTH via Current.flow_depth (re-entrada SÍNCRONA inline de
# flows — o re-trigger async por evento NÃO é coberto por este contador; ver o comentário
# em Current#flow_depth). Ver plano §2.5.
class Flows::RunnerService
  MAX_STEPS = 100
  MAX_DEPTH = 3

  def initialize(flow:, conversation:, actor: nil, trigger_payload: {})
    @flow = flow
    @conversation = conversation
    @actor = actor
    @payload = trigger_payload.to_h.with_indifferent_access
    @graph = (flow.definition || {}).with_indifferent_access
  end

  def perform
    with_depth_guard { walk }
  ensure
    Current.reset
  end

  # Nota (revisão adversarial): NÃO replicamos o `mark_as_unread!`-na-reatribuição do
  # Macros::ExecutionService — o Conversation já o faz nativamente via
  # AssignmentHandler#mark_conversation_unread_on_assignment_change (after_commit em
  # assignee_id/team_id, assignment_handler.rb:8). Replicar marcaria a conversa não-lida
  # duas vezes. O macro o faz por legado, anterior a esse callback.

  private

  def walk
    actions = Flows::ActionService.new(flow: @flow, conversation: @conversation, actor: @actor)
    node_id = start_node_id
    steps = 0
    while node_id && (steps += 1) <= MAX_STEPS
      node = find_node(node_id)
      break if node.nil?

      branch = visit(node, actions)
      node_id = next_node_id(node_id, branch)
    end
  end

  def visit(node, actions)
    case node['type']
    when 'action'
      actions.execute(node)
      nil
    when 'condition', 'router'
      evaluate_condition(node) ? 'true' : 'false'
    end
    # 'trigger' e tipos desconhecidos são no-op: caem aqui retornando nil e o fluxo segue
    # pela primeira aresta de saída (o trigger é apenas o ponto de entrada).
  end

  def evaluate_condition(node)
    adapter = Flows::RuleAdapter.new(conditions: node['conditions'], flow: @flow)
    AutomationRules::ConditionsFilterService.new(adapter, @conversation, @payload).perform
  end

  def nodes
    @graph.fetch('nodes', [])
  end

  def edges
    @graph.fetch('edges', [])
  end

  def find_node(node_id)
    nodes.find { |node| node['id'] == node_id }
  end

  # Raiz = primeiro nó que não é destino de nenhuma aresta (ou o primeiro, se não há arestas).
  def start_node_id
    target_ids = edges.filter_map { |edge| edge['to'] }
    entry = nodes.find { |node| target_ids.exclude?(node['id']) }
    (entry || nodes.first)&.dig('id')
  end

  # Segue a aresta de saída. Com `branch` (condition/router) casa o ramo pelo rótulo, com
  # fallback para a aresta sem rótulo; sem branch, a primeira aresta de saída.
  def next_node_id(node_id, branch)
    outgoing = edges.select { |edge| edge['from'] == node_id }
    edge = if branch
             outgoing.find { |e| e['branch'].to_s == branch } || outgoing.find { |e| e['branch'].blank? }
           else
             outgoing.first
           end
    edge && edge['to']
  end

  def with_depth_guard
    Current.flow_depth = (Current.flow_depth || 0) + 1
    yield if Current.flow_depth <= MAX_DEPTH
  ensure
    Current.flow_depth -= 1 if Current.flow_depth
  end
end
