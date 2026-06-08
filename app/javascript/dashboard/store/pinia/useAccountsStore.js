import { defineStore, acceptHMRUpdate } from 'pinia';
import { differenceInDays } from 'date-fns';
import AccountAPI from '../../api/account';
import EnterpriseAccountAPI from '../../api/enterprise/account';
import { throwErrorMessage } from '../utils/api';
import { getLanguageDirection } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import { useAuthStore } from './useAuthStore';

const TRIAL_PERIOD_DAYS = 15;

// Espelho Pinia de store/modules/accounts.js (Onda 1 P0-05).
export const useAccountsStore = defineStore('accounts', {
  state: () => ({
    records: [],
    limitsEndpointUnavailableByAccount: {},
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isUpdating: false,
      isCheckoutInProcess: false,
      isFetchingLimits: false,
    },
  }),

  getters: {
    getAccount: state => id =>
      state.records.find(r => r.id === Number(id)) || {},
    getUIFlags: state => state.uiFlags,
    isRTL(state) {
      const auth = useAuthStore();
      const accountId = Number(auth.currentAccountId);
      const userLocale = auth.getUISettings?.locale;
      const accountLocale =
        accountId &&
        (state.records.find(r => r.id === accountId) || {})?.locale;
      const effectiveLocale = userLocale ?? accountLocale;
      return effectiveLocale ? getLanguageDirection(effectiveLocale) : false;
    },
    isTrialAccount: state => id => {
      const account = state.records.find(r => r.id === Number(id)) || {};
      const createdAt = new Date(account.created_at);
      const diffDays = differenceInDays(new Date(), createdAt);
      return diffDays <= TRIAL_PERIOD_DAYS;
    },
    isFeatureEnabledonAccount: state => (id, featureName) => {
      const { features = {} } =
        state.records.find(r => r.id === Number(id)) || {};
      return features[featureName] || false;
    },
    isLimitsEndpointUnavailable: state => accountId => {
      const id = Number(accountId);
      if (!id) return false;
      return Boolean(state.limitsEndpointUnavailableByAccount[id]);
    },
  },

  actions: {
    upsertRecord(record) {
      const index = this.records.findIndex(r => r.id === record.id);
      if (index > -1) this.records.splice(index, 1, record);
      else this.records.push(record);
    },

    async get() {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await AccountAPI.get();
        this.upsertRecord(response.data);
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async update({ options, ...updateObj }) {
      if (options?.silent !== true) {
        this.uiFlags.isUpdating = true;
      }
      try {
        const response = await AccountAPI.update('', updateObj);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete({ id }) {
      this.uiFlags.isUpdating = true;
      try {
        await AccountAPI.delete(id);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async toggleDeletion({ action_type } = { action_type: 'delete' }) {
      this.uiFlags.isUpdating = true;
      try {
        await EnterpriseAccountAPI.toggleDeletion(action_type);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async create(accountInfo) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AccountAPI.createAccount(accountInfo);
        return response.data.data.account_id;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async checkout() {
      this.uiFlags.isCheckoutInProcess = true;
      try {
        const response = await EnterpriseAccountAPI.checkout();
        window.location = response.data.redirect_url;
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCheckoutInProcess = false;
      }
    },

    async subscription() {
      this.uiFlags.isCheckoutInProcess = true;
      try {
        await EnterpriseAccountAPI.subscription();
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCheckoutInProcess = false;
      }
    },

    async limits() {
      const auth = useAuthStore();
      const accountId = Number(auth.getCurrentAccountId);
      if (accountId && this.limitsEndpointUnavailableByAccount?.[accountId]) {
        return null;
      }

      this.uiFlags.isFetchingLimits = true;
      try {
        const response = await EnterpriseAccountAPI.getLimits();
        // SET_ACCOUNT_LIMITS = updateAttributes do MutationHelpers
        const data = response.data;
        const index = this.records.findIndex(r => r.id === data.id);
        if (index > -1) {
          this.records.splice(index, 1, { ...this.records[index], ...data });
        }
        if (accountId) {
          this.limitsEndpointUnavailableByAccount = {
            ...this.limitsEndpointUnavailableByAccount,
            [accountId]: false,
          };
        }
        return response;
      } catch (error) {
        if (error?.response?.status === 404 && accountId) {
          this.limitsEndpointUnavailableByAccount = {
            ...this.limitsEndpointUnavailableByAccount,
            [accountId]: true,
          };
        }
        return null;
      } finally {
        this.uiFlags.isFetchingLimits = false;
      }
    },

    async getCacheKeys() {
      return AccountAPI.getCacheKeys();
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAccountsStore, import.meta.hot));
}
