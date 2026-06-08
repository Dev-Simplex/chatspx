import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import { forceCleanReload } from '../helper/autoUpdateHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';

// Helper: chega no /app/accounts/:id/dashboard sem disparar warnings de "no match"
// no caminho. O guard `validateAuthenticateRoutePermission` se encarrega do redirect
// final assim que tiver o currentUser carregado — aqui só evitamos os steps `/app`
// e `/app/` que o vue-router não tem rota literal pra casar.
const resolveAccountDashboard = () => {
  const user = store.getters?.getCurrentUser;
  const accountId = user?.account_id || user?.accounts?.[0]?.id;
  return accountId ? `/app/accounts/${accountId}/dashboard` : '/app/login';
};

const routes = [
  { path: '/', redirect: resolveAccountDashboard },
  { path: '/app', redirect: resolveAccountDashboard },
  { path: '/app/', redirect: resolveAccountDashboard },
  ...dashboard.routes,
];

export const router = createRouter({ history: createWebHistory(), routes });

export const validateAuthenticateRoutePermission = (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  if (to.name === 'no_accounts' || !to.name) {
    return next(frontendURL(`accounts/${accountId}/dashboard`));
  }

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

router.onError(error => {
  if (
    error.message.includes('Failed to fetch dynamically imported module') ||
    error.message.includes('Loading chunk') ||
    error.message.includes('Loading CSS chunk')
  ) {
    forceCleanReload();
  }
});

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach((to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    userAuthentication.then(() => {
      return validateAuthenticateRoutePermission(to, next, store);
    });
  });
};

export default router;
