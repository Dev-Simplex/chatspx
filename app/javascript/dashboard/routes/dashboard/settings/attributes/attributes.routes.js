import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { NOT_TEAM_SUPERVISOR } from 'dashboard/constants/permissions.js';
import SettingsWrapper from '../SettingsWrapper.vue';
import AttributesHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/custom-attributes'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'attributes_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'attributes_list',
          component: AttributesHome,
          meta: {
            featureFlag: FEATURE_FLAGS.CUSTOM_ATTRIBUTES,
            permissions: ['administrator', NOT_TEAM_SUPERVISOR],
          },
        },
      ],
    },
  ],
};
