import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
// Redesign visual (protótipo, dados fictícios). A página funcional antiga
// (InternalChatIndex.vue) segue no disco para revert rápido quando quisermos.
import InternalChatRedesign from './pages/InternalChatRedesign.vue';

const commonMeta = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.INTERNAL_CHAT,
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/internal-chat'),
    component: InternalChatRedesign,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'internal_chat_index',
        component: InternalChatRedesign,
        meta: commonMeta,
      },
    ],
  },
];
