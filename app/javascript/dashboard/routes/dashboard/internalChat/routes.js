import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
// A tela viva do chat interno é a InternalChatRedesign (dados reais). A
// InternalChatIndex.vue está morta: não é importada em lugar nenhum.
// Import dinâmico: o chat vira um chunk próprio e não pesa no boot do painel.
const InternalChatRedesign = () => import('./pages/InternalChatRedesign.vue');

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
