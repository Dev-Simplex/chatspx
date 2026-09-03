import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/units'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'units_list',
          component: Index,
          // Sem NOT_TEAM_SUPERVISOR de propósito: unidade não é configuração de
          // plataforma e não entra nas seis telas que o supervisor perde.
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
