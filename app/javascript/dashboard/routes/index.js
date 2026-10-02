import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import { forceCleanReload } from '../helper/autoUpdateHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';
import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';

const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

export const validateAuthenticateRoutePermission = (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;
  const shortcutAssignee =
    ['/app', '/app/'].includes(to.path) &&
    ['me', 'unassigned'].includes(to.query?.assignee_type)
      ? to.query.assignee_type
      : null;

  if (!isLoggedIn) {
    if (shortcutAssignee) {
      SessionStorage.set(
        SESSION_STORAGE_KEYS.PWA_ASSIGNEE_TYPE,
        shortcutAssignee
      );
    }
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

  // Static manifest shortcuts resolve the authenticated account at runtime.
  // Keep the selected queue through login, including MFA, then consume it once.
  if (!to.name || to.name === 'home') {
    const assigneeType =
      shortcutAssignee ||
      SessionStorage.get(SESSION_STORAGE_KEYS.PWA_ASSIGNEE_TYPE);
    SessionStorage.remove(SESSION_STORAGE_KEYS.PWA_ASSIGNEE_TYPE);
    if (['me', 'unassigned'].includes(assigneeType)) {
      return next({
        name: 'home',
        params: { accountId },
        query: { assignee_type: assigneeType },
      });
    }
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
