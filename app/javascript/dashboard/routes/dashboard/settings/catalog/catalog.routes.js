import { frontendURL } from '../../../../helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import CatalogProductForm from './CatalogProductForm.vue';

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
        {
          // `productId` aceita 'new': é o mesmo formulário criando e editando, e é o que a grade
          // já manda quando o botão "Novo produto" é clicado.
          path: ':productId',
          name: 'catalog_product_edit',
          component: CatalogProductForm,
          // Aqui a régua aperta: o `CatalogProductPolicy` só deixa administrador criar e editar,
          // então abrir o formulário para o atendente seria mostrar uma tela que o salvar recusa.
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
