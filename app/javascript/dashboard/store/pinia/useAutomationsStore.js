import { defineStore, acceptHMRUpdate } from 'pinia';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import AutomationAPI from '../../api/automation';

// Espelho Pinia de store/modules/automations.js (Onda 2 P0-05).
export const useAutomationsStore = defineStore('automations', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isDeleting: false,
      isUpdating: false,
      isCloning: false,
    },
  }),

  getters: {
    getAutomations: state => [...state.records].sort((a, b) => a.id - b.id),
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AutomationAPI.get();
        this.records = response.data.payload;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(automationObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AutomationAPI.create(automationObj);
        this.records.push(response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await AutomationAPI.update(id, updateObj);
        const data = response.data.payload;
        const idx = this.records.findIndex(r => r.id === data.id);
        if (idx > -1) this.records.splice(idx, 1, data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await AutomationAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async clone(id) {
      this.uiFlags.isCloning = true;
      try {
        await AutomationAPI.clone(id);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCloning = false;
      }
    },

    async uploadAttachment(file) {
      const { blobId } = await uploadFile(file);
      return blobId;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAutomationsStore, import.meta.hot));
}
