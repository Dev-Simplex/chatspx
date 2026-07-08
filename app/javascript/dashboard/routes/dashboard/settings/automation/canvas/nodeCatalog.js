// Metadados dos nós do canvas F1 (Flow). Cada nó pertence a exatamente uma das 6 famílias
// semânticas do design system (plano §6). O `type` casa com Flow::NODE_TYPES no backend
// (trigger/action/condition/router/wait); para `action`, o `actionName` distingue a ação.
//
// i18n: os rótulos NÃO são strings — são chaves (`labelKey`) resolvidas via `$t`/`t` nos
// componentes (AUTOMATION.CANVAS.FAMILIES.* e AUTOMATION.CANVAS.NODES.*). Assim o catálogo
// permanece um módulo JS puro (sem contexto i18n) e nada fica hardcoded no template.

export const FAMILIES = {
  trigger: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.TRIGGER',
    color: '#0e9f6e',
    colorDark: '#34d399',
  },
  msg: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.MSG',
    color: '#0f8a6f',
    colorDark: '#25d366',
  },
  logic: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.LOGIC',
    color: '#c77a06',
    colorDark: '#fbbf24',
  },
  ai: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.AI',
    color: '#6f63e6',
    colorDark: '#a99bff',
  },
  action: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.ACTION',
    color: '#5b6478',
    colorDark: '#8b93aa',
  },
  data: {
    labelKey: 'AUTOMATION.CANVAS.FAMILIES.DATA',
    color: '#2563c9',
    colorDark: '#5b9bff',
  },
};

// Itens da paleta (F1 linear — read+edit). `labelKey` resolve via i18n AUTOMATION.CANVAS.NODES.*.
export const NODE_CATALOG = [
  {
    key: 'trigger',
    type: 'trigger',
    family: 'trigger',
    labelKey: 'AUTOMATION.CANVAS.NODES.TRIGGER',
    icon: 'i-lucide-zap',
  },
  {
    key: 'condition',
    type: 'condition',
    family: 'logic',
    labelKey: 'AUTOMATION.CANVAS.NODES.CONDITION',
    icon: 'i-lucide-git-branch',
  },
  {
    key: 'router',
    type: 'router',
    family: 'logic',
    labelKey: 'AUTOMATION.CANVAS.NODES.ROUTER',
    icon: 'i-lucide-split',
  },
  {
    key: 'wait',
    type: 'wait',
    family: 'logic',
    labelKey: 'AUTOMATION.CANVAS.NODES.WAIT',
    icon: 'i-lucide-clock',
  },
  {
    key: 'send_message',
    type: 'action',
    actionName: 'send_message',
    family: 'msg',
    labelKey: 'AUTOMATION.CANVAS.NODES.SEND_MESSAGE',
    icon: 'i-lucide-message-square',
  },
  {
    key: 'send_template',
    type: 'action',
    actionName: 'send_template',
    family: 'msg',
    labelKey: 'AUTOMATION.CANVAS.NODES.SEND_TEMPLATE',
    icon: 'i-lucide-file-badge',
  },
  {
    key: 'add_private_note',
    type: 'action',
    actionName: 'add_private_note',
    family: 'msg',
    labelKey: 'AUTOMATION.CANVAS.NODES.ADD_PRIVATE_NOTE',
    icon: 'i-lucide-sticky-note',
  },
  {
    key: 'assign_agent',
    type: 'action',
    actionName: 'assign_agent',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.ASSIGN_AGENT',
    icon: 'i-lucide-user',
  },
  {
    key: 'assign_team',
    type: 'action',
    actionName: 'assign_team',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.ASSIGN_TEAM',
    icon: 'i-lucide-users',
  },
  {
    key: 'add_label',
    type: 'action',
    actionName: 'add_label',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.ADD_LABEL',
    icon: 'i-lucide-tag',
  },
  {
    key: 'change_status',
    type: 'action',
    actionName: 'change_status',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.CHANGE_STATUS',
    icon: 'i-lucide-check-circle',
  },
  {
    key: 'change_priority',
    type: 'action',
    actionName: 'change_priority',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.CHANGE_PRIORITY',
    icon: 'i-lucide-flag',
  },
  {
    key: 'snooze_conversation',
    type: 'action',
    actionName: 'snooze_conversation',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.SNOOZE',
    icon: 'i-lucide-alarm-clock',
  },
  {
    key: 'assign_ai_agent',
    type: 'action',
    actionName: 'assign_ai_agent',
    family: 'ai',
    labelKey: 'AUTOMATION.CANVAS.NODES.ASSIGN_AI_AGENT',
    icon: 'i-lucide-bot',
  },
  {
    key: 'ai_classify',
    type: 'action',
    actionName: 'ai_classify',
    family: 'ai',
    labelKey: 'AUTOMATION.CANVAS.NODES.AI_CLASSIFY',
    icon: 'i-lucide-tags',
  },
  {
    key: 'ai_generate',
    type: 'action',
    actionName: 'ai_generate',
    family: 'ai',
    labelKey: 'AUTOMATION.CANVAS.NODES.AI_GENERATE',
    icon: 'i-lucide-sparkles',
  },
  {
    key: 'set_attribute',
    type: 'action',
    actionName: 'set_attribute',
    family: 'data',
    labelKey: 'AUTOMATION.CANVAS.NODES.SET_ATTRIBUTE',
    icon: 'i-lucide-database',
  },
  {
    key: 'move_funnel_stage',
    type: 'action',
    actionName: 'move_funnel_stage',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.MOVE_FUNNEL_STAGE',
    icon: 'i-lucide-square-kanban',
  },
  {
    key: 'call_macro',
    type: 'action',
    actionName: 'call_macro',
    family: 'action',
    labelKey: 'AUTOMATION.CANVAS.NODES.CALL_MACRO',
    icon: 'i-lucide-wand-sparkles',
  },
  {
    key: 'send_csat',
    type: 'action',
    actionName: 'send_csat',
    family: 'msg',
    labelKey: 'AUTOMATION.CANVAS.NODES.SEND_CSAT',
    icon: 'i-lucide-star',
  },
];

// Entrada do catálogo que descreve um nó da definition. Nós `action` casam pelo actionName
// (null se a ação não estiver no catálogo → o rótulo cai no action_name cru); os demais
// tipos (trigger/condition/wait/router) casam pelo `type`. NÃO comparar actionName quando o
// nó não tem action_name — `undefined === undefined` casaria o 1º item sem actionName (trigger).
export function catalogEntryForNode(node) {
  if (!node) return null;
  if (node.type === 'action') {
    return (
      NODE_CATALOG.find(item => item.actionName === node.action_name) || null
    );
  }
  return NODE_CATALOG.find(item => item.type === node.type) || null;
}

export function familyForNode(node) {
  if (!node) return 'action';
  if (node.type !== 'action') {
    const entry = NODE_CATALOG.find(item => item.type === node.type);
    return entry ? entry.family : 'logic';
  }
  const entry = NODE_CATALOG.find(item => item.actionName === node.action_name);
  return entry ? entry.family : 'action';
}

// Retorna a CHAVE i18n do rótulo do nó (resolver com `t(...)` no componente). Fallback: o
// próprio action_name/type cru — vue-i18n devolve a string literal quando a chave não existe.
export function labelForNode(node) {
  if (!node) return '';
  const entry = catalogEntryForNode(node);
  return entry ? entry.labelKey : node.action_name || node.type || '';
}

// Ícone lucide do nó (para o header do painel de configuração e afins).
export function iconForNode(node) {
  const entry = catalogEntryForNode(node);
  return entry ? entry.icon : 'i-lucide-square';
}
