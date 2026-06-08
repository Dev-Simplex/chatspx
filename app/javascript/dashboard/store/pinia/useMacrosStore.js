import { defineStore, acceptHMRUpdate } from 'pinia';
import MacrosAPI from '../../api/macros';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/macros.js (Onda 1 P0-05).
export const useMacrosStore = defineStore('macros', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetchingItem: false,
      isFetching: false,
      isCreating: false,
      isDeleting: false,
      isUpdating: false,
      isExecuting: false,
    },
  }),

  getters: {
    getMacros: state => state.records,
    getMacro: state => id => state.records.find(r => r.id === Number(id)),
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    upsertRecord(record) {
      const index = this.records.findIndex(r => r.id === record.id);
      if (index > -1) this.records.splice(index, 1, record);
      else this.records.push(record);
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await MacrosAPI.get();
        this.records = response.data.payload;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async getSingleMacro(macroId) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await MacrosAPI.show(macroId);
        this.upsertRecord(response.data.payload);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async create(payload) {
      this.uiFlags.isCreating = true;
      try {
        const response = await MacrosAPI.create(payload);
        this.upsertRecord(response.data.payload);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async execute(payload) {
      this.uiFlags.isExecuting = true;
      try {
        await MacrosAPI.executeMacro(payload);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isExecuting = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await MacrosAPI.update(id, updateObj);
        const index = this.records.findIndex(
          r => r.id === response.data.payload.id
        );
        if (index > -1) this.records.splice(index, 1, response.data.payload);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await MacrosAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useMacrosStore, import.meta.hot));
}
