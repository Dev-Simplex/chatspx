// Metadados dos nós do canvas F1 (Flow). Cada nó pertence a exatamente uma das 6 famílias
// semânticas do design system (plano §6). O `type` casa com Flow::NODE_TYPES no backend
// (trigger/action/condition/router/wait); para `action`, o `actionName` distingue a ação.

export const FAMILIES = {
  trigger: { label: 'TRIGGER', color: '#0e9f6e', colorDark: '#34d399' },
  msg: { label: 'MSG', color: '#0f8a6f', colorDark: '#25d366' },
  logic: { label: 'LOGIC', color: '#c77a06', colorDark: '#fbbf24' },
  ai: { label: 'AI', color: '#6f63e6', colorDark: '#a99bff' },
  action: { label: 'ACTION', color: '#5b6478', colorDark: '#8b93aa' },
  data: { label: 'DATA', color: '#2563c9', colorDark: '#5b9bff' },
};

// Itens arrastáveis da paleta (F1 linear — read+edit). labelKey resolve via i18n AUTOMATION.CANVAS.*.
export const NODE_CATALOG = [
  {
    key: 'trigger',
    type: 'trigger',
    family: 'trigger',
    label: 'Gatilho',
    icon: 'i-lucide-zap',
  },
  {
    key: 'condition',
    type: 'condition',
    family: 'logic',
    label: 'Condição',
    icon: 'i-lucide-git-branch',
  },
  {
    key: 'send_message',
    type: 'action',
    actionName: 'send_message',
    family: 'msg',
    label: 'Enviar mensagem',
    icon: 'i-lucide-message-square',
  },
  {
    key: 'send_template',
    type: 'action',
    actionName: 'send_template',
    family: 'msg',
    label: 'Enviar template',
    icon: 'i-lucide-file-badge',
  },
  {
    key: 'add_private_note',
    type: 'action',
    actionName: 'add_private_note',
    family: 'msg',
    label: 'Nota interna',
    icon: 'i-lucide-sticky-note',
  },
  {
    key: 'assign_agent',
    type: 'action',
    actionName: 'assign_agent',
    family: 'action',
    label: 'Atribuir agente',
    icon: 'i-lucide-user',
  },
  {
    key: 'assign_team',
    type: 'action',
    actionName: 'assign_team',
    family: 'action',
    label: 'Atribuir time',
    icon: 'i-lucide-users',
  },
  {
    key: 'add_label',
    type: 'action',
    actionName: 'add_label',
    family: 'action',
    label: 'Etiqueta',
    icon: 'i-lucide-tag',
  },
  {
    key: 'change_status',
    type: 'action',
    actionName: 'change_status',
    family: 'action',
    label: 'Mudar status',
    icon: 'i-lucide-check-circle',
  },
  {
    key: 'change_priority',
    type: 'action',
    actionName: 'change_priority',
    family: 'action',
    label: 'Prioridade',
    icon: 'i-lucide-flag',
  },
  {
    key: 'assign_ai_agent',
    type: 'action',
    actionName: 'assign_ai_agent',
    family: 'ai',
    label: 'Transferir p/ IA',
    icon: 'i-lucide-bot',
  },
  {
    key: 'set_attribute',
    type: 'action',
    actionName: 'set_attribute',
    family: 'data',
    label: 'Definir atributo',
    icon: 'i-lucide-database',
  },
];

export function familyForNode(node) {
  if (!node) return 'action';
  if (node.type !== 'action') {
    const entry = NODE_CATALOG.find(item => item.type === node.type);
    return entry ? entry.family : 'logic';
  }
  const entry = NODE_CATALOG.find(item => item.actionName === node.action_name);
  return entry ? entry.family : 'action';
}

export function labelForNode(node) {
  if (!node) return '';
  const entry =
    NODE_CATALOG.find(item => item.actionName === node.action_name) ||
    NODE_CATALOG.find(item => item.type === node.type);
  return entry ? entry.label : node.action_name || node.type;
}
