// Conversão AutomationRule clássica <-> `definition` do canvas, feita 100% client-side (sem
// depender do backfill do servidor). Permite "abrir no canvas" uma regra antiga para revisão
// antes de salvá-la como Flow.
//
// O mapeamento das AÇÕES é fiel ao `Flows::BackfillService#actions_to_definition`
// (app/services/flows/backfill_service.rb): cada ação, na ordem, vira um nó
// `{ id, type: 'action', action_name, action_params }` encadeado linearmente por arestas
// `{ from, to }`. Aqui somamos, na frente da cadeia, os nós que o canvas usa para exibir o
// gatilho e o filtro da regra:
//   trigger (event_name)  →  condition (conditions)  →  ação  →  ação  →  …
// As ações penduram no ramo `true` da condition (quando há condições); sem condições, saem
// diretas do trigger, em cadeia linear — exatamente o formato degenerado do backfill.

// Aresta encadeadora. `branch` só é gravado quando existe (fluxo linear = Handle padrão),
// espelhando como FlowCanvasView#onConnect e o backfill representam arestas sem ramo.
const chainEdge = (from, to, branch) =>
  branch ? { from, to, branch } : { from, to };

// AutomationRule ({ event_name, conditions, actions }) -> definition ({ nodes, edges }).
export function flatToDefinition(rule = {}) {
  const eventName = rule.event_name;
  const conditions = Array.isArray(rule.conditions) ? rule.conditions : [];
  const actions = Array.isArray(rule.actions) ? rule.actions : [];

  const nodes = [];
  const edges = [];
  let counter = 0;
  const nextId = () => {
    counter += 1;
    return `n${counter}`;
  };

  // Gatilho: com event_name a regra abre como conversation_event (FlowCanvasView#triggerPayload
  // lê node.event_name); sem ele, um gatilho vazio (o usuário escolhe no TriggerConfig).
  const triggerId = nextId();
  const triggerNode = { id: triggerId, type: 'trigger' };
  if (eventName) triggerNode.event_name = eventName;
  nodes.push(triggerNode);

  let tailId = triggerId;
  let tailBranch;

  // Condição: as conditions da regra viram um nó `condition`; as ações penduram no ramo `true`.
  if (conditions.length) {
    const conditionId = nextId();
    nodes.push({ id: conditionId, type: 'condition', conditions });
    edges.push(chainEdge(tailId, conditionId, tailBranch));
    tailId = conditionId;
    tailBranch = 'true';
  }

  // Ações encadeadas — fiel ao actions_to_definition.
  actions.forEach(action => {
    const actionId = nextId();
    nodes.push({
      id: actionId,
      type: 'action',
      action_name: action.action_name,
      action_params: action.action_params,
    });
    edges.push(chainEdge(tailId, actionId, tailBranch));
    tailId = actionId;
    tailBranch = undefined;
  });

  return { nodes, edges };
}

// definition ({ nodes, edges }) -> AutomationRule ({ event_name, conditions, actions }).
// Percorre a cadeia a partir do gatilho, coletando as ações na ordem de travessia (seguindo o
// ramo `true` ao sair de uma condition, senão a aresta linear). Inverso de flatToDefinition.
export function definitionToFlat(definition = {}) {
  const nodes = Array.isArray(definition.nodes) ? definition.nodes : [];
  const edges = Array.isArray(definition.edges) ? definition.edges : [];

  const trigger = nodes.find(node => node.type === 'trigger');
  const condition = nodes.find(node => node.type === 'condition');
  const byId = new Map(nodes.map(node => [String(node.id), node]));

  const actions = [];
  const seen = new Set();
  let currentId = trigger
    ? String(trigger.id)
    : (nodes[0] && String(nodes[0].id)) || null;

  while (currentId && !seen.has(currentId)) {
    const nodeId = currentId; // binding por iteração — evita closure sobre a var do loop
    seen.add(nodeId);
    const node = byId.get(nodeId);
    if (node && node.type === 'action') {
      actions.push({
        action_name: node.action_name,
        action_params: node.action_params,
      });
    }
    const outgoing = edges.filter(edge => String(edge.from) === nodeId);
    const next =
      node && node.type === 'condition'
        ? outgoing.find(edge => String(edge.branch) === 'true') || outgoing[0]
        : outgoing.find(edge => edge.branch == null) || outgoing[0];
    currentId = next ? String(next.to) : null;
  }

  return {
    event_name: trigger?.event_name || null,
    conditions: condition?.conditions || [],
    actions,
  };
}
