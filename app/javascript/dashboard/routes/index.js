import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import { reloadWhenSafe } from '../helper/autoUpdateHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

const CHUNK_LOAD_ERROR_PATTERN =
  /(Failed to fetch dynamically imported module|Loading chunk|Loading CSS chunk)/;
let chunkRetryInFlight = false;

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

router.onError(async (error, to) => {
  if (!CHUNK_LOAD_ERROR_PATTERN.test(error.message)) return;

  // Pos-deploy is the dominant cause of chunk-load errors (stale index.html
  // pointing at chunks that were just replaced). Retry the navigation once
  // after a short delay before nuking the session — most of the time the
  // CDN/nginx serves the new chunk and the reload is avoided entirely.
  if (chunkRetryInFlight) {
    reloadWhenSafe();
    return;
  }
  chunkRetryInFlight = true;
  await new Promise(resolve => {
    setTimeout(resolve, 500);
  });
  try {
    await router.push(to.fullPath);
    chunkRetryInFlight = false;
  } catch {
    chunkRetryInFlight = false;
    reloadWhenSafe();
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
