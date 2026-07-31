# frozen_string_literal: true

# Percorre o grafo do Flow (nodes+edges) reusando o ActionService inteiro. Nós `action`
# executam; `condition`/`router` avaliam e escolhem o ramo; `wait` (Fase 2) SUSPENDE o
# passo: grava o estado num FlowRun e para — o Flows::ResumeJob retoma quando o wait vence,
# reentrando o walker no nó salvo. Fluxos SEM wait continuam lineares e síncronos e NÃO
# criam FlowRun (o estado só existe entre execuções, quando há suspensão). Guardas:
# MAX_STEPS (ciclo no grafo por aresta malformada, por passo de execução) e MAX_DEPTH via
# Current.flow_depth (re-entrada SÍNCRONA inline de flows — o re-trigger async por evento
# NÃO é coberto por este contador; ver o comentário em Current#flow_depth). Ver plano §2.5.
#
# DISPARO REAL: #perform (início) / #resume_from (retomada pós-wait). SIMULAÇÃO (dry-run, Fase
# 3.3): #simulate — percorre o MESMO grafo sem efetivar nada (ver Flows::SimulationService).
class Flows::RunnerService
  # Instrumentação do DISPARO REAL: roda a ação/ramo e grava o FlowStepLog (trilha de auditoria,
  # best-effort). Extraído p/ manter esta classe enxuta. Ver Flows::StepInstrumentation.
  include Flows::StepInstrumentation
  # Comportamento do walker em modo SIMULAÇÃO (dry_run): descreve ações em vez de executá-las e
  # atravessa `wait` em vez de suspender. Ver Flows::SimulationWalk e Flows::SimulationService.
  include Flows::SimulationWalk
  # Nó `wait_for_reply` (F2): suspende esperando a resposta do contato e, na retomada, ramifica pela
  # opção escolhida ou por 'timeout'. Extraído p/ manter esta classe enxuta. Ver Flows::ReplyWait.
  include Flows::ReplyWait
  # Saida anomala do walker (estouro de MAX_STEPS = ciclo no grafo). Ver Flows::WalkGuard.
  include Flows::WalkGuard

  MAX_STEPS = 100
  MAX_DEPTH = 3
  WAIT_UNITS = %w[minutes hours days].freeze
  DEFAULT_WAIT_UNIT = 'minutes'
  DEFAULT_WAIT_VALUE = 1
  # Sentinela interna de #step_node: sinaliza ao #walk que um `wait` suspendeu o disparo real e o
  # laço deve parar. Não é um branch — branches são strings/nil, então nunca colidem com este símbolo.
  HALT = :halt

  # Lista ORDENADA dos passos simulados, populada SÓ pelo #simulate (fica [] no disparo real).
  # A Flows::SimulationService a lê. Ver Flows::SimulationWalk#simulate_visit para o formato.
  attr_reader :simulation_steps

  # rubocop:disable Metrics/ParameterLists
  def initialize(flow:, conversation:, actor: nil, trigger_payload: {}, flow_run: nil, resume_reply: nil)
    # rubocop:enable Metrics/ParameterLists
    @flow = flow
    @conversation = conversation
    @actor = actor
    @payload = trigger_payload.to_h.with_indifferent_access
    @graph = (flow.definition || {}).with_indifferent_access
    # Presente só na retomada (Flows::ResumeService o injeta): assim um novo `wait` ATUALIZA
    # o mesmo run em vez de criar outro. No disparo inicial nasce nil e é materializado
    # preguiçosamente no primeiro `wait`.
    @flow_run = flow_run
    # Presente só na retomada por MENSAGEM (Flows::ReplyResumeService injeta a resposta do
    # contato): { id, title }. Com resposta, o wait_for_reply ramifica pelo id da opção; SEM ela
    # (retomada por TEMPO/timeout e disparo inicial) nasce nil e ramifica por 'timeout'. Ver
    # #evaluate_reply_branch.
    @resume_reply = resume_reply&.to_h&.with_indifferent_access
    # Nó de reentrada da retomada (gravado por #resume_from). Distingue, num wait_for_reply, o
    # "1º toque no walk pra frente" (SUSPENDE) da "retomada NESTE nó" (RAMIFICA). Ver
    # #suspend_on_wait_for_reply.
    @resume_start_id = nil
    # dry_run desligado por padrão: #perform/#resume_from são o disparo REAL, idêntico ao de hoje.
    # Só o #simulate liga o flag (a assinatura do construtor fica intacta p/ os chamadores atuais).
    @dry_run = false
    @simulation_steps = []
  end

  # Disparo do início do grafo (manual/evento). Caminha síncrono até o grafo acabar OU um
  # nó `wait` suspender o passo. Só materializa FlowRun se houver wait.
  #
  # O reset é obrigatório: o Current (lib/current.rb) NÃO é ActiveSupport::CurrentAttributes, é um
  # módulo com thread_mattr_accessor — nada o limpa sozinho no fim do job, e o Sidekiq REUSA as
  # threads do pool. Sem o reset, o `Current.executed_by = flow` que o Flows::ActionService seta no
  # construtor vazaria para o próximo job da mesma thread. Aqui é seguro resetar no ensure porque
  # o #perform roda FORA de transação: cada update! já commitou (e seus after_commit já rodaram)
  # antes de chegarmos no reset. Na retomada NÃO é — ver #resume_from.
  def perform
    with_depth_guard { walk(start_node_id) }
  ensure
    Current.reset
  end

  # Ponto de entrada da SIMULAÇÃO (Flows::SimulationService, base da Fase 3.3). Liga o dry-run e
  # percorre o MESMO grafo do #perform seguindo condition/router como no ar, MAS sem efetivar
  # NADA — nenhuma ação executada, `wait` atravessado, nada persistido (nem FlowStepLog, nem
  # FlowRun, nem a conversa). Devolve os passos simulados. INOCUIDADE POR CONSTRUÇÃO: com dry_run
  # ligado, #walk nem instancia o Flows::ActionService (a única porta de efeito colateral).
  def simulate
    @dry_run = true
    with_depth_guard { walk(start_node_id) }
    simulation_steps
  ensure
    Current.reset
  end

  # Retomada: continua do nó que o wait apontou (o sucessor, já salvo em current_node_id).
  # Chamado por Flows::ResumeService depois que wait_until venceu; @flow_run é o run
  # persistido, então um novo wait o ATUALIZA em vez de criar outro.
  #
  # NÃO reseta o Current (ao contrário de #perform/#simulate): os dois chamadores da retomada
  # (Flows::ResumeService e Flows::ReplyResumeService) reentram DENTRO de um `with_lock`, ou seja,
  # com uma transação ABERTA. Um reset aqui rodaria antes do COMMIT e apagaria o contexto que os
  # after_commit da Conversation leem — o create_team_change_activity depende de
  # Current.executed_by e, sem ele, a activity "Atribuído a <time> por Sistema de Automação" nunca
  # nasce (e o dispatch sai com performed_by nil, enfraquecendo o anti-loop do
  # AutomationRuleListener). Por isso o reset é responsabilidade de QUEM ABRIU o contexto: os dois
  # services o fazem num `ensure` DEPOIS que o with_lock fecha (commit já efetivado). Ver o
  # comentário de #perform sobre o porquê do reset existir.
  def resume_from(node_id)
    # Guarda o nó de reentrada: quando ele é um wait_for_reply, #suspend_on_wait_for_reply o
    # reconhece e NÃO re-suspende — deixa o #visit ramificar pela resposta/timeout.
    @resume_start_id = node_id
    with_depth_guard { walk(node_id) }
  end

  # Nota (revisão adversarial): NÃO replicamos o `mark_as_unread!`-na-reatribuição do
  # Macros::ExecutionService — o Conversation já o faz nativamente via
  # AssignmentHandler#mark_conversation_unread_on_assignment_change (after_commit em
  # assignee_id/team_id, assignment_handler.rb:8). Replicar marcaria a conversa não-lida
  # duas vezes. O macro o faz por legado, anterior a esse callback.

  private

  def walk(node_id)
    actions = build_walk_actions
    steps = 0
    while node_id && (steps += 1) <= MAX_STEPS
      node = find_node(node_id)
      break if node.nil?

      branch = step_node(node, node_id, actions)
      return if branch == HALT # disparo real: um `wait` suspendeu o passo (estado já persistido)

      node_id = next_node_id(node_id, branch)
    end

    # Sair pelo TETO (e não por node_id nil / nó inexistente) é ciclo no grafo — não é conclusão.
    return fail_on_step_limit if steps > MAX_STEPS

    finish_run unless @dry_run # no dry-run não há FlowRun a completar (nada foi persistido)
  end

  # INOCUIDADE POR CONSTRUÇÃO: no dry-run NÃO instanciamos o Flows::ActionService — a ÚNICA porta
  # para efetivar uma ação (#execute manda mensagem, grava atributo, chama IA…). Sem a instância,
  # #execute é literalmente inalcançável: a simulação não tem como disparar nada.
  def build_walk_actions
    return if @dry_run

    Flows::ActionService.new(flow: @flow, conversation: @conversation, actor: @actor)
  end

  # Processa UM nó e devolve o `branch` a seguir (condition/router) ou nil (action/wait/etc). No
  # dry-run apenas DESCREVE/AVALIA (nunca executa, suspende ou persiste). No disparo real, um `wait`
  # suspende o passo e devolvemos HALT para o walker parar o laço (estado já persistido).
  def step_node(node, node_id, actions)
    return simulate_visit(node) if @dry_run
    return HALT if suspend_on_wait(node, node_id)
    return HALT if suspend_on_wait_for_reply(node, node_id)

    visit(node, actions)
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
      persist_suspension(node_id: successor, wait_until: wait_until_for(node))
    end
    true
  end

  # Grava a suspensão (node_id de reentrada + wait_until) num FlowRun, materializando-o
  # preguiçosamente no disparo inicial ou atualizando o existente na retomada. Reusado pelo `wait`
  # (grava o sucessor) e pelo `wait_for_reply` (grava o próprio nó).
  def persist_suspension(node_id:, wait_until:)
    run = flow_run
    run.suspend!(node_id: node_id, wait_until: wait_until)
    @flow_run = run
  rescue ActiveRecord::RecordNotUnique
    # Perdeu a corrida com outro run in-flight desta (flow, conversation); reusa-o pra os
    # dois disparos convergirem num só row (o índice único parcial é a última linha de defesa).
    existing = FlowRun.where(status: FlowRun::ACTIVE_STATUSES).find_by(flow: @flow, conversation: @conversation)
    existing&.suspend!(node_id: node_id, wait_until: wait_until)
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

  # Config do wait: { value: N, unit: 'minutes'|'hours'|'days', business_hours: bool } em
  # node['wait'] (ou, como fallback, node['action_params'], que segue o formato de array das
  # outras ações). Ausente ou inválido → 1 minuto: um wait malconfigurado retoma no próximo
  # tick em vez de martelar (value<=0) ou esperar pra sempre (unit inválida). Com
  # `business_hours: true` o instante calculado é empurrado para a próxima abertura comercial
  # da inbox da conversa se cair fora do expediente (Flows::BusinessHours; no-op se a inbox não
  # tem working hours ligado).
  def wait_until_for(node)
    w = normalized_wait(node)
    base = w[:value].public_send(w[:unit]).from_now
    # `business_hours` aceita boolean nativo ou string ('true'/'1') — o canvas grava no JSON.
    return base unless ActiveModel::Type::Boolean.new.cast(w[:business_hours])

    Flows::BusinessHours.next_opening(@conversation.inbox, from: base)
  end

  # Normaliza a config do wait (mesma lógica no disparo real e na descrição do dry-run): value<=0
  # → 1; unit inválida → 'minutes'. Ver o comentário de #wait_until_for para o porquê dos defaults.
  def normalized_wait(node)
    normalize_wait_config(wait_config(node))
  end

  # Núcleo da normalização, reusado pelo `wait` (config em node['wait']) e pelo timeout do
  # `wait_for_reply` (config em node['timeout']): value<=0 → 1; unit inválida → 'minutes'.
  def normalize_wait_config(cfg)
    cfg = (cfg || {}).to_h.with_indifferent_access
    value = cfg['value'].to_i
    value = DEFAULT_WAIT_VALUE if value <= 0
    unit = WAIT_UNITS.include?(cfg['unit']) ? cfg['unit'] : DEFAULT_WAIT_UNIT
    { value: value, unit: unit, business_hours: cfg['business_hours'] }
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

  # Executa o nó e devolve o branch tomado (condition/router) ou nil (action). Cada nó
  # EXECUTADO grava um FlowStepLog best-effort — ver #record_step (uma falha do log NUNCA
  # derruba o walk). `trigger`/`wait`/tipos desconhecidos não executam: o walker apenas os
  # atravessa pela primeira aresta de saída (o `wait` já foi tratado por suspend_on_wait
  # antes de chegar aqui; o trigger é só o ponto de entrada).
  def visit(node, actions)
    case node['type']
    when 'action'
      instrument_action(node, actions)
      nil
    when 'condition'
      instrument_branch(node) { evaluate_condition(node) ? 'true' : 'false' }
    when 'router'
      instrument_branch(node) { evaluate_router(node) }
    when 'wait_for_reply'
      instrument_branch(node) { evaluate_reply_branch(node) }
    end
  end

  def evaluate_condition(node)
    conditions_match?(node['conditions'])
  end

  # Router first-match (EXECUTE_FIRST_MATCH): avalia as rotas ORDENADAS e devolve a `key` da
  # PRIMEIRA cujas condições casam. Rota sem condições nunca casa (uma rota em branco não pode
  # engolir tudo). Nenhuma casa → `fallback_key` (o ramo "senão"). A aresta é escolhida por
  # `next_node_id` casando `edge['branch'] == key`; a aresta sem rótulo é a última rede.
  def evaluate_router(node)
    routes = node['routes']
    routes = [] unless routes.is_a?(Array)
    matched = routes.find do |route|
      conditions = route['conditions']
      conditions.present? && conditions_match?(conditions)
    end
    (matched && matched['key'].to_s.presence) || node['fallback_key'].to_s.presence || 'fallback'
  end

  # Reusa o motor de condição inteiro via RuleAdapter (`conditions` na forma GERADA).
  def conditions_match?(conditions)
    adapter = Flows::RuleAdapter.new(conditions: conditions, flow: @flow)
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
