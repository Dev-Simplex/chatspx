import { defineStore, acceptHMRUpdate } from 'pinia';
import authAPI from '../../api/auth';
import { setUser, clearCookiesOnLogout } from '../utils/api';
import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import { useAgentsStore } from './useAgentsStore';

const initialCurrentUser = () => ({
  id: null,
  account_id: null,
  accounts: [],
  email: null,
  name: null,
});

// Espelho Pinia de store/modules/auth.js (Onda 1 P0-05).
// Persiste currentUser em localStorage via pinia-plugin-persistedstate.
export const useAuthStore = defineStore('auth', {
  state: () => ({
    currentUser: initialCurrentUser(),
    uiFlags: { isFetching: true },
    // currentAccountId vem da rota no Vuex (rootState.route). Pinia nao
    // tem essa janela; setamos explicitamente via setCurrentAccountId.
    currentAccountId: null,
  }),

  getters: {
    isLoggedIn: state => !!state.currentUser.id,
    getCurrentUserID: state => state.currentUser.id,
    getUISettings: state => state.currentUser.ui_settings || {},
    getAuthUIFlags: state => state.uiFlags,
    getCurrentAccountId: state => state.currentAccountId,
    getCurrentAccount(state) {
      const { accounts = [] } = state.currentUser;
      return (
        accounts.find(account => account.id === state.currentAccountId) || {}
      );
    },
    getCurrentUserAvailability() {
      return this.getCurrentAccount.availability;
    },
    getCurrentUserAutoOffline() {
      return this.getCurrentAccount.auto_offline;
    },
    getCurrentRole() {
      return this.getCurrentAccount.role;
    },
    getCurrentCustomRoleId() {
      return this.getCurrentAccount.custom_role_id;
    },
    getCurrentUser: state => state.currentUser,
    getMessageSignature: state => state.currentUser.message_signature || '',
    getUserAccounts: state => state.currentUser.accounts || [],
  },

  actions: {
    setCurrentAccountId(accountId) {
      this.currentAccountId = accountId ? Number(accountId) : null;
    },

    async validityCheck() {
      try {
        const response = await authAPI.validityCheck();
        const currentUser = response.data.payload.data;
        setUser(currentUser);
        this.currentUser = currentUser;
      } catch (error) {
        if (error?.response?.status === 401) {
          clearCookiesOnLogout();
        }
      }
    },

    async setUser() {
      if (authAPI.hasAuthCookie()) {
        await this.validityCheck();
      } else {
        this.currentUser = initialCurrentUser();
      }
      this.uiFlags = { isFetching: false };
    },

    logout() {
      this.currentUser = initialCurrentUser();
    },

    async updateProfile(params) {
      const response = await authAPI.profileUpdate(params);
      this.currentUser = response.data;
    },

    async updatePassword(params) {
      const response = await authAPI.profilePasswordUpdate(params);
      this.currentUser = response.data;
    },

    async deleteAvatar() {
      try {
        const response = await authAPI.deleteAvatar();
        this.currentUser = response.data;
      } catch (error) {
        // Ignore error
      }
    },

    async updateUISettings({ uiSettings }) {
      try {
        this.currentUser = {
          ...this.currentUser,
          ui_settings: {
            ...this.currentUser.ui_settings,
            ...uiSettings,
          },
        };

        const isImpersonating = SessionStorage.get(
          SESSION_STORAGE_KEYS.IMPERSONATION_USER
        );

        if (!isImpersonating) {
          const response = await authAPI.updateUISettings({ uiSettings });
          this.currentUser = response.data;
        }
      } catch (error) {
        // Ignore error
      }
    },

    setAvailabilityOnCurrentAccount(availability) {
      const accounts = this.currentUser.accounts.map(account => {
        if (account.id === this.currentUser.account_id) {
          return {
            ...account,
            availability,
            availability_status: availability,
          };
        }
        return account;
      });
      this.currentUser = { ...this.currentUser, accounts };
    },

    setAutoOfflineOnCurrentAccount(autoOffline) {
      const accounts = this.currentUser.accounts.map(account => {
        if (account.id === this.currentUser.account_id) {
          return { ...account, autoOffline };
        }
        return account;
      });
      this.currentUser = { ...this.currentUser, accounts };
    },

    async updateAvailability(params) {
      const previousStatus = this.getCurrentUserAvailability;
      try {
        this.setAvailabilityOnCurrentAccount(params.availability);
        const response = await authAPI.updateAvailability(params);
        const { id } = response.data;
        this.currentUser = response.data;
        useAgentsStore().updateSingleAgentPresence({
          id,
          availabilityStatus: params.availability,
        });
      } catch (error) {
        this.setAvailabilityOnCurrentAccount(previousStatus);
      }
    },

    async updateAutoOffline({ accountId, autoOffline }) {
      const previousAutoOffline = this.getCurrentUserAutoOffline;
      try {
        this.setAutoOfflineOnCurrentAccount(autoOffline);
        const response = await authAPI.updateAutoOffline(
          accountId,
          autoOffline
        );
        this.currentUser = response.data;
      } catch (error) {
        this.setAutoOfflineOnCurrentAccount(previousAutoOffline);
      }
    },

    setCurrentUserAvailability(data) {
      if (data[this.currentUser.id]) {
        this.setAvailabilityOnCurrentAccount(data[this.currentUser.id]);
      }
    },

    async setActiveAccount({ accountId }) {
      try {
        await authAPI.setActiveAccount({ accountId });
      } catch (error) {
        // Ignore error
      }
    },

    async resetAccessToken() {
      try {
        const response = await authAPI.resetAccessToken();
        this.currentUser = response.data;
        return true;
      } catch (error) {
        return false;
      }
    },

    async resendConfirmation() {
      try {
        await authAPI.resendConfirmation();
      } catch (error) {
        // Ignore error
      }
    },
  },

  persist: {
    key: 'chatspx-auth',
    paths: ['currentUser', 'currentAccountId'],
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAuthStore, import.meta.hot));
}
