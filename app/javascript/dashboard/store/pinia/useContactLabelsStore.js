import { defineStore, acceptHMRUpdate } from 'pinia';
import ContactAPI from '../../api/contacts';

// Espelho Pinia de store/modules/contactLabels.js (Onda 2 P0-05).
export const useContactLabelsStore = defineStore('contactLabels', {
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
    getContactLabels: state => id => state.records[Number(id)] || [],
  },

  actions: {
    async get(contactId) {
      this.uiFlags.isFetching = true;
      try {
        const response = await ContactAPI.getContactLabels(contactId);
        this.records = { ...this.records, [contactId]: response.data.payload };
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async update({ contactId, labels }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await ContactAPI.updateContactLabels(
          contactId,
          labels
        );
        this.records = { ...this.records, [contactId]: response.data.payload };
        this.uiFlags.isUpdating = false;
        this.uiFlags.isError = false;
      } catch (error) {
        this.uiFlags.isUpdating = false;
        this.uiFlags.isError = true;
        throw new Error(error);
      }
    },

    setContactLabel({ id, data }) {
      this.records = { ...this.records, [id]: data };
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useContactLabelsStore, import.meta.hot)
  );
}
