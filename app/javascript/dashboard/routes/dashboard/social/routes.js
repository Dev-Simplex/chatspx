import { frontendURL } from 'dashboard/helper/URLHelper';

const SocialPage = () => import('./SocialPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/rede-social'),
    name: 'social_index',
    component: SocialPage,
    meta: {
      permissions: ['administrator'],
    },
  },
];

export default { routes };
