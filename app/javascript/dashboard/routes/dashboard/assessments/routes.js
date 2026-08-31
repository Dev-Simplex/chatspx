import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions';

const AssessmentsPage = () => import('./AssessmentsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/assessments'),
    name: 'assessments_index',
    component: AssessmentsPage,
    meta: { permissions: ROLES },
  },
];
