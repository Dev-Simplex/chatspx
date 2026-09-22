import { frontendURL } from '../../../../helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/catalog'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'catalog_products_index',
          component: Index,
          // Mesma régua do `CatalogProductPolicy#index?`: ler o catálogo é do atendente também,
          // porque é ele quem manda o produto na conversa. Cadastrar é que é de administrador.
          meta: { permissions: [...ROLES] },
        },
      ],
    },
  ],
};
