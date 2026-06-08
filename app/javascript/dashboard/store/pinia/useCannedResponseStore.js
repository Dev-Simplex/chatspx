import { defineStore, acceptHMRUpdate } from 'pinia';
import CannedResponseAPI from '../../api/cannedResponse';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/cannedResponse.js (Onda 1 P0-05).
export const useCannedResponseStore = defineStore('cannedResponse', {
  state: () => ({
    records: [],
    uiFlags: {
      fetchingList: false,
      fetchingItem: false,
      creatingItem: false,
      updatingItem: false,
      deletingItem: false,
    },
  }),

  getters: {
    getCannedResponses: state => state.records,
    getSortedCannedResponses: state => sortOrder =>
      [...state.records].sort((a, b) => {
        if (sortOrder === 'asc') {
          return a.short_code.localeCompare(b.short_code);
        }
        return b.short_code.localeCompare(a.short_code);
      }),
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async getCannedResponse({ searchKey } = {}) {
      this.uiFlags.fetchingList = true;
      try {
        const response = await CannedResponseAPI.get({ searchKey });
        this.records = response.data;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    async createCannedResponse(payload) {
      this.uiFlags.creatingItem = true;
      try {
        const response = await CannedResponseAPI.create(payload);
        this.records.push(response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.creatingItem = false;
      }
    },

    async updateCannedResponse({ id, ...updateObj }) {
      this.uiFlags.updatingItem = true;
      try {
        const response = await CannedResponseAPI.update(id, updateObj);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.updatingItem = false;
      }
    },

    async deleteCannedResponse(id) {
      this.uiFlags.deletingItem = true;
      try {
        await CannedResponseAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
        return id;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.deletingItem = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useCannedResponseStore, import.meta.hot)
  );
}
