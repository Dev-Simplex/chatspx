import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions';

const Index = () => import('./Index.vue');
const CatalogProductForm = () => import('./CatalogProductForm.vue');
const CatalogCategories = () => import('./CatalogCategories.vue');
const CatalogFields = () => import('./CatalogFields.vue');
const CatalogIntegrations = () => import('./CatalogIntegrations.vue');

const base = 'accounts/:accountId/catalog';
const soAdministrador = { permissions: ['administrator'] };

export const routes = [
  {
    path: frontendURL(base),
    name: 'catalog_products_index',
    component: Index,
    // Mesma régua do `CatalogProductPolicy#index?`: ler o catálogo é do atendente também,
    // porque é ele quem manda o item na conversa. Cadastrar é que é de administrador.
    meta: { permissions: [...ROLES] },
  },
  {
    path: frontendURL(`${base}/categories`),
    name: 'catalog_categories',
    component: CatalogCategories,
    meta: soAdministrador,
  },
  {
    path: frontendURL(`${base}/fields`),
    name: 'catalog_fields',
    component: CatalogFields,
    meta: soAdministrador,
  },
  {
    path: frontendURL(`${base}/integrations`),
    name: 'catalog_integrations',
    component: CatalogIntegrations,
    meta: soAdministrador,
  },
  {
    // `productId` aceita 'new': é o mesmo formulário criando e editando.
    path: frontendURL(`${base}/items/:productId`),
    name: 'catalog_product_edit',
    component: CatalogProductForm,
    // O `CatalogProductPolicy` só deixa administrador criar e editar, então abrir o formulário
    // para o atendente seria mostrar uma tela que o salvar recusa.
    meta: soAdministrador,
  },
  // O catálogo morava em Configurações. Link salvo e favorito antigo continuam chegando.
  {
    path: frontendURL('accounts/:accountId/settings/catalog'),
    redirect: to => ({
      name: 'catalog_products_index',
      params: { accountId: to.params.accountId },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/settings/catalog/:productId'),
    redirect: to => ({
      name: 'catalog_product_edit',
      params: {
        accountId: to.params.accountId,
        productId: to.params.productId,
      },
    }),
  },
];
