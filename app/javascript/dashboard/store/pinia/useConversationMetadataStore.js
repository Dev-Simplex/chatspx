import { defineStore, acceptHMRUpdate } from 'pinia';

// Espelho Pinia de store/modules/conversationMetadata.js (Onda 2 P0-05).
export const useConversationMetadataStore = defineStore(
  'conversationMetadata',
  {
    state: () => ({
      records: {},
    }),

    getters: {
      getConversationMetadata: state => id => state.records[Number(id)] || {},
    },

    actions: {
      setConversationMetadata({ id, data }) {
        this.records = { ...this.records, [id]: data };
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationMetadataStore, import.meta.hot)
  );
}
