/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import IntegrationsAPI from '../../api/integrations';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Espelho Pinia de store/modules/integrations.js (Onda 2 P0-05).
export const useIntegrationsStore = defineStore('integrations', {
  state: () => ({
    records: [],
    uiFlags: {
      isCreating: false,
      isFetching: false,
      isFetchingItem: false,
      isUpdating: false,
      isCreatingHook: false,
      isDeletingHook: false,
      isCreatingSlack: false,
      isUpdatingSlack: false,
      isFetchingSlackChannels: false,
    },
  }),

  getters: {
    getAppIntegrations: state => state.records,
    getIntegration:
      state =>
      (integrationId, defaultValue = {}) =>
        state.records.find(r => r.id === integrationId) || defaultValue,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    _applyAttributes(data) {
      const index = this.records.findIndex(r => r.id === data.id);
      if (index > -1) {
        this.records.splice(index, 1, { ...this.records[index], ...data });
      }
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await IntegrationsAPI.get();
        this.records = response.data.payload;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async connectSlack(code) {
      this.uiFlags.isCreatingSlack = true;
      try {
        const response = await IntegrationsAPI.connectSlack(code);
        this._applyAttributes(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreatingSlack = false;
      }
    },

    async updateSlack(slackObj) {
      this.uiFlags.isUpdatingSlack = true;
      try {
        const response = await IntegrationsAPI.updateSlack(slackObj);
        this._applyAttributes(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdatingSlack = false;
      }
    },

    async listAllSlackChannels() {
      this.uiFlags.isFetchingSlackChannels = true;
      try {
        const response = await IntegrationsAPI.listAllSlackChannels();
        return response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingSlackChannels = false;
      }
      return null;
    },

    async deleteIntegration(integrationId) {
      this.uiFlags.isDeleting = true;
      try {
        await IntegrationsAPI.delete(integrationId);
        this._applyAttributes({ id: integrationId, enabled: false });
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async showHook(hookId) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await IntegrationsAPI.showHook(hookId);
        this._addIntegrationHook(response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async createHook(hookData) {
      this.uiFlags.isCreatingHook = true;
      try {
        const response = await IntegrationsAPI.createHook(hookData);
        this._addIntegrationHook(response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreatingHook = false;
      }
    },

    async deleteHook({ appId, hookId }) {
      this.uiFlags.isDeletingHook = true;
      try {
        await IntegrationsAPI.deleteHook(hookId);
        this.records = this.records.map(record => {
          if (record.id === appId) {
            return {
              ...record,
              hooks: record.hooks.filter(h => h.id !== hookId),
            };
          }
          return record;
        });
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeletingHook = false;
      }
    },

    _addIntegrationHook(data) {
      this.records = this.records.map(record => {
        if (record.id === data.app_id) {
          return {
            ...record,
            hooks: [...record.hooks, data],
          };
        }
        return record;
      });
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useIntegrationsStore, import.meta.hot)
  );
}
