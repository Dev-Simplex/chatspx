import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import InternalChatIndex from './pages/InternalChatIndex.vue';

const commonMeta = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.INTERNAL_CHAT,
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/internal-chat'),
    component: InternalChatIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'internal_chat_index',
        component: InternalChatIndex,
        meta: commonMeta,
      },
    ],
  },
];
