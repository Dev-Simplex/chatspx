import { defineStore, acceptHMRUpdate } from 'pinia';
import BulkActionsAPI from '../../api/bulkActions';

// Espelho Pinia de store/modules/bulkActions.js (Onda 2 P0-05).
export const useBulkActionsStore = defineStore('bulkActions', {
  state: () => ({
    selectedConversationIds: [],
    uiFlags: {
      isUpdating: false,
    },
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getSelectedConversationIds: state => state.selectedConversationIds,
  },

  actions: {
    async process(payload) {
      this.uiFlags.isUpdating = true;
      try {
        await BulkActionsAPI.create(payload);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    setSelectedConversationIds(ids) {
      const idsArray = Array.isArray(ids) ? ids : [ids];
      this.selectedConversationIds = [
        ...new Set([...this.selectedConversationIds, ...idsArray]),
      ];
    },

    removeSelectedConversationIds(id) {
      this.selectedConversationIds = this.selectedConversationIds.filter(
        item => item !== id
      );
    },

    clearSelectedConversationIds() {
      this.selectedConversationIds = [];
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useBulkActionsStore, import.meta.hot));
}
