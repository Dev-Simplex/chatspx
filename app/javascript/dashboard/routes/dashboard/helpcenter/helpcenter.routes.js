import { FEATURE_FLAGS } from '../../../featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions';
import { isHelpCenterAuthoringAccount } from 'dashboard/helper/helpCenterEmbed';
import { getPortalRoute } from './helpers/routeHelper';

import HelpCenterPageRouteView from './pages/HelpCenterPageRouteView.vue';
import PortalsIndex from './pages/PortalsIndexPage.vue';
import PortalsNew from './pages/PortalsNewPage.vue';

const HelpCenterEmbedPage = () => import('./pages/HelpCenterEmbedPage.vue');
const SuggestionsPage = () => import('./pages/SuggestionsPage.vue');
const SuggestionsSentPage = () => import('./pages/SuggestionsSentPage.vue');

// Fora da conta autora (conta 3 do deploy de casa) o construtor de artigos
// não existe: qualquer rota `portals_*` cai no iframe somente-leitura.
const redirectNonAuthoringToEmbed = (to, from, next) => {
  if (isHelpCenterAuthoringAccount(to.params.accountId)) {
    next();
    return;
  }
  next({
    name: 'help_center_view',
    params: { accountId: to.params.accountId },
  });
};

const PortalsArticlesIndexPage = () =>
  import('./pages/PortalsArticlesIndexPage.vue');
const PortalsArticlesNewPage = () =>
  import('./pages/PortalsArticlesNewPage.vue');
const PortalsArticlesEditPage = () =>
  import('./pages/PortalsArticlesEditPage.vue');

const PortalsCategoriesIndexPage = () =>
  import('./pages/PortalsCategoriesIndexPage.vue');

const PortalsLocalesIndexPage = () =>
  import('./pages/PortalsLocalesIndexPage.vue');

const PortalsSettingsIndexPage = () =>
  import('./pages/PortalsSettingsIndexPage.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.HELP_CENTER,
  permissions: ['administrator', 'agent', 'knowledge_base_manage'],
};
const portalRoutes = [
  {
    path: getPortalRoute(':portalSlug/:locale/:categorySlug?/articles/:tab?'),
    name: 'portals_articles_index',
    meta,
    component: PortalsArticlesIndexPage,
  },
  {
    path: getPortalRoute(':portalSlug/:locale/:categorySlug?/articles/new'),
    name: 'portals_articles_new',
    meta,
    component: PortalsArticlesNewPage,
  },
  {
    path: getPortalRoute(
      ':portalSlug/:locale/:categorySlug?/articles/:tab?/edit/:articleSlug'
    ),
    name: 'portals_articles_edit',
    meta,
    component: PortalsArticlesEditPage,
  },

  {
    path: getPortalRoute(':portalSlug/:locale/categories'),
    name: 'portals_categories_index',
    meta,
    component: PortalsCategoriesIndexPage,
  },
  {
    path: getPortalRoute(
      ':portalSlug/:locale/categories/:categorySlug/articles'
    ),
    name: 'portals_categories_articles_index',
    meta,
    component: PortalsArticlesIndexPage,
  },
  {
    path: getPortalRoute(
      ':portalSlug/:locale/categories/:categorySlug/articles/:articleSlug'
    ),
    name: 'portals_categories_articles_edit',
    meta,
    component: PortalsArticlesEditPage,
  },
  {
    path: getPortalRoute(':portalSlug/locales'),
    name: 'portals_locales_index',
    meta,
    component: PortalsLocalesIndexPage,
  },
  {
    path: getPortalRoute(':portalSlug/settings'),
    name: 'portals_settings_index',
    meta,
    component: PortalsSettingsIndexPage,
  },
  {
    path: getPortalRoute('new'),
    name: 'portals_new',
    meta: {
      featureFlag: FEATURE_FLAGS.HELP_CENTER,
      permissions: ['administrator', 'knowledge_base_manage'],
    },
    component: PortalsNew,
  },
  {
    path: getPortalRoute(':navigationPath'),
    name: 'portals_index',
    meta: {
      featureFlag: FEATURE_FLAGS.HELP_CENTER,
      permissions: ['administrator', 'knowledge_base_manage'],
    },
    component: PortalsIndex,
  },
];

export default {
  routes: [
    {
      // Caixa de sugestões (SUG-01). SEM featureFlag de propósito: quem tem a Central de Ajuda
      // desligada continua podendo mandar ideia de melhoria para a Simplex.
      path: frontendURL('accounts/:accountId/suggestions'),
      name: 'suggestions_new',
      component: SuggestionsPage,
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
    {
      // Lista das enviadas, em item próprio do menu (pedido do dono em 29/09).
      path: frontendURL('accounts/:accountId/suggestions/sent'),
      name: 'suggestions_sent',
      component: SuggestionsSentPage,
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
    },
    {
      // Central de Ajuda embutida (iframe do portal publicado). Visível a
      // todos os papéis — é somente leitura. Todas as contas caem aqui, menos
      // a conta autora, que continua no construtor abaixo.
      path: frontendURL('accounts/:accountId/help-center'),
      name: 'help_center_view',
      component: HelpCenterEmbedPage,
      meta: {
        permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      },
    },
    {
      path: getPortalRoute(),
      component: HelpCenterPageRouteView,
      redirect: to => {
        return {
          name: 'portals_index',
          params: {
            navigationPath: 'portals_articles_index',
            ...to.params,
          },
        };
      },
      children: portalRoutes.map(route => ({
        ...route,
        beforeEnter: redirectNonAuthoringToEmbed,
      })),
    },
  ],
};
