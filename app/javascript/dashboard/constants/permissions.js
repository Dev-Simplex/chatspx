export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
];

export const ROLES = ['agent', 'administrator'];

// Supervisor de time. Chega no `permissions` da conta pelo backend
// (AccountUser#supervision_permissions), ao lado de 'administrator'/'agent'.
export const TEAM_SUPERVISOR = 'team_supervisor';

// NEGAÇÃO no `meta.permissions` de uma rota: o prefixo `!` diz "quem tiver esta
// permissão NÃO entra", mesmo sendo administrador. Precisa existir porque
// `hasPermissions` é um OU — sem isso 'administrator' sozinho já liberaria a rota.
// Mora no MESMO array do "quem pode" para as duas regras nunca se separarem, e
// cobre menu e URL de uma vez: os dois caminhos passam por `hasPermissions`.
export const denyPermission = permission => `!${permission}`;
export const NOT_TEAM_SUPERVISOR = denyPermission(TEAM_SUPERVISOR);

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  // Abas do modo IA (gate ON), dinâmicas — filtragem em ChatList.vue.
  // "Rodízio": admin/supervisor sempre; agente só quando há conversa na vez dele.
  rodizio: {
    count: 'rodizioCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  // "Atenção": conversas que a IA marcou para um humano julgar o fecho. Só
  // admin e supervisor (o backend devolve vazio para os demais).
  pending_closure: {
    count: 'awaitingClosureCount',
    permissions: ['administrator', TEAM_SUPERVISOR],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  // Order of the keys dictates the tab order (Mine / [Awaiting] / [Unassigned] / AI / All)
  ai: {
    count: 'aiCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};
