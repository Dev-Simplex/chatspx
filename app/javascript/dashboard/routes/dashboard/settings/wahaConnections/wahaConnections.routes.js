import { frontendURL } from '../../../../helper/URLHelper';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/connections'),
      name: 'waha_connections_list',
      meta: {
        permissions: ['administrator'],
      },
      component: () => import('./Index.vue'),
    },
  ],
};


