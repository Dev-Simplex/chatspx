import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';

import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  NOT_TEAM_SUPERVISOR,
} from 'dashboard/constants/permissions.js';

// Macros é uma das seis telas fora do alcance do supervisor de time. Vale também
// para o supervisor AGENTE — esta tela era visível a agentes, ao contrário das
// outras cinco. EXECUTAR macro dentro da conversa continua valendo para todos:
// é outro caminho (MacroPolicy#execute?), não esta rota.
const MACROS_PERMISSIONS = [
  ...ROLES,
  ...CONVERSATION_PERMISSIONS,
  NOT_TEAM_SUPERVISOR,
];
import SettingsContent from '../Wrapper.vue';
import SettingsWrapper from '../SettingsWrapper.vue';
import Macros from './Index.vue';
import MacroEditor from './MacroEditor.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/macros'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'macros_wrapper',
          component: Macros,
          meta: {
            featureFlag: FEATURE_FLAGS.MACROS,
            permissions: MACROS_PERMISSIONS,
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/macros'),
      component: SettingsContent,
      props: () => {
        return {
          headerTitle: 'MACROS.HEADER',
          icon: 'flash-settings',
          showBackButton: true,
        };
      },
      children: [
        {
          path: ':macroId/edit',
          name: 'macros_edit',
          component: MacroEditor,
          meta: {
            featureFlag: FEATURE_FLAGS.MACROS,
            permissions: MACROS_PERMISSIONS,
          },
        },
        {
          path: 'new',
          name: 'macros_new',
          component: MacroEditor,
          meta: {
            featureFlag: FEATURE_FLAGS.MACROS,
            permissions: MACROS_PERMISSIONS,
          },
        },
      ],
    },
  ],
};
