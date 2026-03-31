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
    ],
  },
];
