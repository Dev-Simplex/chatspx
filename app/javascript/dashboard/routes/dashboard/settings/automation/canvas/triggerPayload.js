// A PROJEÇÃO DO GATILHO: nó `trigger` da definition -> { trigger_type, trigger_config } que o
// backend consome. A fonte da verdade continua sendo o nó na definition; aqui só derivamos o que
// o motor lê.
//
// Saiu de dentro de `FlowCanvasView.vue` no bloco 4.02 porque é uma função pura que decide o que
// vai ser GRAVADO, e o defeito que este bloco conserta era exatamente um ramo faltando nela: um
// fluxo de captura caía no default `manual` e o `trigger_config` ia vazio, apagando a segmentação
// inteira no servidor (que aplica o jsonb cru). Fora do SFC ela é testável com o dado real, sem
// montar o canvas.
//
//  • trigger_kind 'widget_prechat' → widget_prechat + a segmentação ECOADA (bloco 4.02)
//  • trigger_kind 'keyword'        → keyword + { keywords[], match, direction }
//  • trigger_kind 'schedule'       → schedule + { mode, cron | every, unit }
//  • trigger_kind 'webhook'        → external_webhook + {} (o backend gera/preserva o
//    webhook_token — nunca o cliente; ver Flow#ensure_webhook_token)
//  • event_name definido           → conversation_event + { event_name, direction }
//  • nada disso                    → manual

/** O `trigger_kind` do fluxo de captura do chat de site. Espelha o enum `Flow#trigger_type`. */
export const WIDGET_PRECHAT_KIND = 'widget_prechat';

const keywordConfig = triggerNode => ({
  keywords: (triggerNode.keywords || [])
    .map(kw => (kw || '').trim())
    .filter(Boolean),
  match: triggerNode.match === 'exact' ? 'exact' : 'contains',
  direction: triggerNode.direction || 'both',
});

const scheduleConfig = triggerNode => {
  const sched = triggerNode.schedule || {};
  if (sched.mode === 'interval') {
    const every = Number.parseInt(sched.every, 10);
    return {
      mode: 'interval',
      every: Number.isNaN(every) || every < 1 ? 1 : every,
      unit: ['minutes', 'hours', 'days'].includes(sched.unit)
        ? sched.unit
        : 'days',
    };
  }
  return { mode: 'cron', cron: String(sched.cron ?? '').trim() };
};

// O gatilho de captura é testado ANTES do `event_name` de propósito: um fluxo que já foi
// `conversation_event` e virou captura chega carregando o `event_name` antigo no nó, e sem esta
// ordem ele voltaria a ser gravado como evento.
const triggerPayload = (triggerNode, widgetPrechatConfig) => {
  if (!triggerNode) return { trigger_type: 'manual', trigger_config: {} };
  if (triggerNode.trigger_kind === WIDGET_PRECHAT_KIND) {
    return {
      trigger_type: WIDGET_PRECHAT_KIND,
      trigger_config: { ...(widgetPrechatConfig || {}) },
    };
  }
  if (triggerNode.trigger_kind === 'webhook') {
    return { trigger_type: 'external_webhook', trigger_config: {} };
  }
  if (triggerNode.trigger_kind === 'keyword') {
    return {
      trigger_type: 'keyword',
      trigger_config: keywordConfig(triggerNode),
    };
  }
  if (triggerNode.trigger_kind === 'schedule') {
    return {
      trigger_type: 'schedule',
      trigger_config: scheduleConfig(triggerNode),
    };
  }
  if (triggerNode.event_name) {
    return {
      trigger_type: 'conversation_event',
      trigger_config: {
        event_name: triggerNode.event_name,
        direction: triggerNode.direction || 'both',
      },
    };
  }
  return { trigger_type: 'manual', trigger_config: {} };
};

/**
 * O par { trigger_type, trigger_config } do fluxo, a partir dos nós `trigger` da definition.
 *
 * Multi-gatilho: com mais de um nó `trigger` de evento, grava TODOS os event_names em
 * `trigger_config.event_names` — o backend (`current_account_flows`) casa qualquer um.
 * Retrocompat: com um só, mantém apenas `event_name` (`event_names` ausente).
 *
 * @param {Array<object>} triggerNodes os nós `type: 'trigger'` da definition, na ordem
 * @param {object} [widgetPrechatConfig] a segmentação da captura, como o servidor a entregou —
 *   ECOADA, nunca autorada aqui (ver `stampTriggerKind`)
 * @returns {{trigger_type: string, trigger_config: object}}
 */
export const buildTriggerPayload = (triggerNodes, widgetPrechatConfig) => {
  const nodes = triggerNodes || [];
  const payload = triggerPayload(nodes[0], widgetPrechatConfig);
  if (payload.trigger_type !== 'conversation_event') return payload;

  const eventNames = [
    ...new Set(nodes.map(node => node.event_name).filter(Boolean)),
  ];
  if (eventNames.length <= 1) return payload;

  return {
    ...payload,
    trigger_config: { ...payload.trigger_config, event_names: eventNames },
  };
};

/**
 * A IDA do round-trip: carimba `trigger_kind: 'widget_prechat'` nos nós `trigger` de um fluxo de
 * captura, para que a volta (`buildTriggerPayload`) saiba o que ele é.
 *
 * O carimbo é só o KIND, e é assim que o canvas já representa todos os outros gatilhos — um
 * modelo da galeria nasce com `trigger_kind: 'keyword'` no nó (`flowTemplates.js`). A
 * SEGMENTAÇÃO não entra na `definition` de propósito: ela mora em `flows.trigger_config`, e
 * gravar uma cópia dela numa segunda coluna criaria um retrato que envelhece — a próxima pessoa
 * que ler `definition` acharia que está lendo o alvo em vigor. O canvas a carrega em memória e a
 * devolve intacta no save (ver `FlowCanvasView#widgetPrechatConfig`).
 *
 * Sem este carimbo o `buildTriggerPayload` não teria como saber que o fluxo é de captura: a
 * definition não carrega o `trigger_type`, ele vem na raiz do flow.
 *
 * @param {object} definition a definition carregada ({ nodes, edges })
 * @param {object} flow o flow como o servidor o serializou
 * @returns {object} uma definition NOVA (imutável — a do store não é tocada)
 */
export const stampTriggerKind = (definition, flow) => {
  const base = definition || { nodes: [], edges: [] };
  if (flow?.trigger_type !== WIDGET_PRECHAT_KIND) return base;

  return {
    ...base,
    nodes: (base.nodes || []).map(node =>
      node.type === 'trigger'
        ? { ...node, trigger_kind: WIDGET_PRECHAT_KIND }
        : node
    ),
  };
};
