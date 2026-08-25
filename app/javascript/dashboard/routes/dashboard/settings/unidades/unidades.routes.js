import { frontendURL } from '../../../../helper/URLHelper';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/unidades'),
      name: 'unidades_list',
      meta: {
        permissions: ['administrator'],
      },
      component: () => import('./Index.vue'),
    },
  ],
};
