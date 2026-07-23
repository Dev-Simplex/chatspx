import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

const TakeoverRequestsPage = () => import('./TakeoverRequestsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/takeover-requests'),
    name: 'takeover_requests_index',
    component: TakeoverRequestsPage,
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
  },
];
