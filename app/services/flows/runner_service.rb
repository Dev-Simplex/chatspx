# frozen_string_literal: true

# Percorre o grafo do Flow (nodes+edges) reusando o ActionService inteiro. Nós `action`
# executam; `condition`/`router` avaliam e escolhem o ramo; `wait` (Fase 2) SUSPENDE o
# passo: grava o estado num FlowRun e para — o Flows::ResumeJob retoma quando o wait vence,
# reentrando o walker no nó salvo. Fluxos SEM wait continuam lineares e síncronos e NÃO
# criam FlowRun (o estado só existe entre execuções, quando há suspensão). Guardas:
# MAX_STEPS (ciclo no grafo por aresta malformada, por passo de execução) e MAX_DEPTH via
# Current.flow_depth (re-entrada SÍNCRONA inline de flows — o re-trigger async por evento
# NÃO é coberto por este contador; ver o comentário em Current#flow_depth). Ver plano §2.5.
class Flows::RunnerService
  MAX_STEPS = 100
  MAX_DEPTH = 3
  WAIT_UNITS = %w[minutes hours days].freeze
  DEFAULT_WAIT_UNIT = 'minutes'
  DEFAULT_WAIT_VALUE = 1

  def initialize(flow:, conversation:, actor: nil, trigger_payload: {}, flow_run: nil)
    @flow = flow
    @conversation = conversation
    @actor = actor
    @payload = trigger_payload.to_h.with_indifferent_access
    @graph = (flow.definition || {}).with_indifferent_access
    # Presente só na retomada (Flows::ResumeService o injeta): assim um novo `wait` ATUALIZA
    # o mesmo run em vez de criar outro. No disparo inicial nasce nil e é materializado
    # preguiçosamente no primeiro `wait`.
    @flow_run = flow_run
  end

  # Disparo do início do grafo (manual/evento). Caminha síncrono até o grafo acabar OU um
  # nó `wait` suspender o passo. Só materializa FlowRun se houver wait.
  def perform
    with_depth_guard { walk(start_node_id) }
  ensure
    Current.reset
  end

  # Retomada: continua do nó que o wait apontou (o sucessor, já salvo em current_node_id).
  # Chamado por Flows::ResumeService depois que wait_until venceu; @flow_run é o run
  # persistido, então um novo wait o ATUALIZA em vez de criar outro.
  def resume_from(node_id)
    with_depth_guard { walk(node_id) }
  ensure
    Current.reset
  end

  # Nota (revisão adversarial): NÃO replicamos o `mark_as_unread!`-na-reatribuição do
  # Macros::ExecutionService — o Conversation já o faz nativamente via
  # AssignmentHandler#mark_conversation_unread_on_assignment_change (after_commit em
  # assignee_id/team_id, assignment_handler.rb:8). Replicar marcaria a conversa não-lida
  # duas vezes. O macro o faz por legado, anterior a esse callback.

  private

  def walk(node_id)
    actions = Flows::ActionService.new(flow: @flow, conversation: @conversation, actor: @actor)
    steps = 0
    while node_id && (steps += 1) <= MAX_STEPS
      node = find_node(node_id)
      break if node.nil?

      return if suspend_on_wait(node, node_id) # `wait` pausa o passo; estado já persistido

      branch = visit(node, actions)
      node_id = next_node_id(node_id, branch)
    end
    finish_run
  end

  # Ao chegar num nó `wait`: grava ONDE retomar (o sucessor do wait) e QUANDO (wait_until) e
  # PARA este passo. Retorna true quando suspendeu, pra o walker sair do laço. Um wait sem
  # sucessor não tem pra onde retomar, então apenas finaliza o run (não deixa um waiting
  # morto ocupando o índice único).
  def suspend_on_wait(node, node_id)
    return false unless node['type'] == 'wait'

    successor = next_node_id(node_id, nil)
    if successor.nil?
      finish_run
    else
      persist_suspension(successor, node)
    end
    true
  end

  def persist_suspension(successor, node)
    run = flow_run
    run.suspend!(node_id: successor, wait_until: wait_until_for(node))
    @flow_run = run
  rescue ActiveRecord::RecordNotUnique
    # Perdeu a corrida com outro run in-flight desta (flow, conversation); reusa-o pra os
    # dois disparos convergirem num só row (o índice único parcial é a última linha de defesa).
    existing = FlowRun.where(status: FlowRun::ACTIVE_STATUSES).find_by(flow: @flow, conversation: @conversation)
    existing&.suspend!(node_id: successor, wait_until: wait_until_for(node))
    @flow_run = existing
  end

  # Materializa o run preguiçosamente (disparo inicial). Na retomada @flow_run já veio da
  # ResumeService, então devolve-o intacto. Construído SEM salvar — o suspend! faz o INSERT
  # já em :waiting (sem row :active transitório vazando).
  def flow_run
    @flow_run ||= FlowRun.new(
      flow: @flow, account: @flow.account, conversation: @conversation,
      contact: @conversation.contact, context: @payload
    )
  end

  # Config do wait: { value: N, unit: 'minutes'|'hours'|'days' } em node['wait'] (ou, como
  # fallback, node['action_params'], que segue o formato de array das outras ações). Ausente
  # ou inválido → 1 minuto: um wait malconfigurado retoma no próximo tick em vez de martelar
  # (value<=0) ou esperar pra sempre (unit inválida).
  def wait_until_for(node)
    cfg = wait_config(node)
    value = cfg['value'].to_i
    value = DEFAULT_WAIT_VALUE if value <= 0
    unit = WAIT_UNITS.include?(cfg['unit']) ? cfg['unit'] : DEFAULT_WAIT_UNIT
    value.public_send(unit).from_now
  end

  def wait_config(node)
    raw = node['wait'] || node['action_params']
    raw = raw.first if raw.is_a?(Array)
    (raw || {}).to_h.with_indifferent_access
  end

  # Completa o run persistido (retomada que chegou ao fim, ou wait sem sucessor). No disparo
  # linear sem wait @flow_run é nil e isto é no-op — nenhum row é criado.
  def finish_run
    @flow_run&.complete!
  end

  def visit(node, actions)
    case node['type']
    when 'action'
      actions.execute(node)
      nil
    when 'condition', 'router'
      evaluate_condition(node) ? 'true' : 'false'
    end
    # 'trigger', 'wait' já tratado antes, e tipos desconhecidos: no-op retornando nil e o
    # fluxo segue pela primeira aresta de saída (o trigger é apenas o ponto de entrada).
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
