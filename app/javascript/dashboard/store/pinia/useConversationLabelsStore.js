import { defineStore, acceptHMRUpdate } from 'pinia';
import ConversationAPI from '../../api/conversations';

// Espelho Pinia de store/modules/conversationLabels.js (Onda 2 P0-05).
export const useConversationLabelsStore = defineStore('conversationLabels', {
  state: () => ({
    records: {},
    uiFlags: {
      isFetching: false,
      isUpdating: false,
      isError: false,
    },
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getConversationLabels: state => id => state.records[Number(id)] || [],
  },

  actions: {
    async get(conversationId) {
      this.uiFlags.isFetching = true;
      try {
        const response = await ConversationAPI.getLabels(conversationId);
        this.records = {
          ...this.records,
          [conversationId]: response.data.payload,
        };
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async update({ conversationId, labels }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await ConversationAPI.updateLabels(
          conversationId,
          labels
        );
        this.records = {
          ...this.records,
          [conversationId]: response.data.payload,
        };
        this.uiFlags.isUpdating = false;
        this.uiFlags.isError = false;
      } catch (error) {
        this.uiFlags.isUpdating = false;
        this.uiFlags.isError = true;
      }
    },

    setBulkConversationLabels(conversations) {
      const updated = { ...this.records };
      conversations.forEach(c => {
        updated[c.id] = c.labels;
      });
      this.records = updated;
    },

    setConversationLabel({ id, data }) {
      this.records = { ...this.records, [id]: data };
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationLabelsStore, import.meta.hot)
  );
}
