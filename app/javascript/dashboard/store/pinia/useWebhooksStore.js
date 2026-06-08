/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import webHookAPI from '../../api/webhooks';

// Espelho Pinia de store/modules/webhooks.js (Onda 2 P0-05).
export const useWebhooksStore = defineStore('webhooks', {
  state: () => ({
    records: [],
    uiFlags: {
      fetchingList: false,
      creatingItem: false,
      deletingItem: false,
      updatingItem: false,
    },
  }),

  getters: {
    getWebhooks: state => [...state.records].sort((w1, w2) => w1.id - w2.id),
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async get() {
      this.uiFlags.fetchingList = true;
      try {
        const response = await webHookAPI.get();
        this.records = response.data.payload.webhooks;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    async create(params) {
      this.uiFlags.creatingItem = true;
      try {
        const response = await webHookAPI.create(params);
        const {
          payload: { webhook },
        } = response.data;
        this.records.push(webhook);
        return webhook;
      } catch (error) {
        throw error;
      } finally {
        this.uiFlags.creatingItem = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.updatingItem = true;
      try {
        const response = await webHookAPI.update(id, updateObj);
        const webhook = response.data.payload.webhook;
        const idx = this.records.findIndex(r => r.id === webhook.id);
        if (idx > -1) this.records.splice(idx, 1, webhook);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.updatingItem = false;
      }
    },

    async delete(id) {
      this.uiFlags.deletingItem = true;
      try {
        await webHookAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
      } catch (error) {
        throw error;
      } finally {
        this.uiFlags.deletingItem = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useWebhooksStore, import.meta.hot));
}
