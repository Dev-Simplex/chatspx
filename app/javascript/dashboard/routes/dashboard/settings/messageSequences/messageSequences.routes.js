import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/message-sequences'),
      name: 'message_sequences_index',
      meta: {
        permissions: ['administrator'],
        featureFlag: FEATURE_FLAGS.MESSAGE_SEQUENCES,
      },
      component: () => import('./Index.vue'),
    },
  ],
};
