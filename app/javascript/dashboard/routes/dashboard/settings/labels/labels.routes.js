import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';

import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/labels'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'labels_wrapper',
          meta: {
            permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
          },
          redirect: to => {
            return { name: 'labels_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'labels_list',
          meta: {
            featureFlag: FEATURE_FLAGS.LABELS,
            permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
          },
          component: Index,
        },
      ],
    },
  ],
};
