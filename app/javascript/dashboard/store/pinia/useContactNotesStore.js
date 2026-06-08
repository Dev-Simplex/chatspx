import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import ContactNotesAPI from '../../api/contactNotes';

// Espelho Pinia de store/modules/contactNotes.js (Onda 2 P0-05).
export const useContactNotesStore = defineStore('contactNotes', {
  state: () => ({
    records: {},
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getAllNotesByContact: state => contactId => {
      const records = state.records[contactId] || [];
      return records.sort((r1, r2) => r2.id - r1.id);
    },
    getUIFlags: state => state.uiFlags,
    getAllNotesByContactId: state => contactId => {
      const records = state.records[contactId] || [];
      const sorted = records.sort((r1, r2) => r2.id - r1.id);
      return camelcaseKeys(sorted);
    },
  },

  actions: {
    async get({ contactId }) {
      this.uiFlags.isFetching = true;
      try {
        const { data } = await ContactNotesAPI.get(contactId);
        this.records = { ...this.records, [contactId]: data };
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create({ contactId, content }) {
      this.uiFlags.isCreating = true;
      try {
        const { data } = await ContactNotesAPI.create(contactId, content);
        const contactNotes = this.records[contactId] || [];
        this.records[contactId] = [...contactNotes, data];
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async delete({ noteId, contactId }) {
      this.uiFlags.isDeleting = true;
      try {
        await ContactNotesAPI.delete(contactId, noteId);
        const contactNotes = this.records[contactId] || [];
        this.records[contactId] = contactNotes.filter(n => n.id !== noteId);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useContactNotesStore, import.meta.hot)
  );
}
