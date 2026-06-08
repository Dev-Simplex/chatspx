import { frontendURL } from '../../../helper/URLHelper';
import KanbanIndex from './pages/KanbanIndex.vue';

const commonMeta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    component: KanbanIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'kanban_index',
        component: KanbanIndex,
        meta: commonMeta,
      },
      {
        path: ':funnelId',
        name: 'kanban_funnel',
        component: KanbanIndex,
        meta: commonMeta,
      },
      {
        // KANBAN-P3 GAP-FIX: rota dedicada para Automações.
        path: ':funnelId/automations',
        name: 'kanban_automations',
        component: KanbanIndex,
        meta: commonMeta,
      },
      {
        // KANBAN-P3 GAP-FIX: rota dedicada para Resumo Diário.
        path: ':funnelId/daily-summary',
        name: 'kanban_daily_summary',
        component: KanbanIndex,
        meta: commonMeta,
      },
    ],
  },
];
