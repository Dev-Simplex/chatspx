import { defineStore, acceptHMRUpdate } from 'pinia';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import CustomRoleAPI from '../../api/customRole';

// Espelho Pinia de store/modules/customRole.js (Onda 2 P0-05).
export const useCustomRoleStore = defineStore('customRole', {
  state: () => ({
    records: [],
    uiFlags: {
      fetchingList: false,
      creatingItem: false,
      updatingItem: false,
      deletingItem: false,
    },
  }),

  getters: {
    getCustomRoles: state => state.records,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async getCustomRole() {
      this.uiFlags.fetchingList = true;
      try {
        const response = await CustomRoleAPI.get();
        this.records = response.data;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    async createCustomRole(customRoleObj) {
      this.uiFlags.creatingItem = true;
      try {
        const response = await CustomRoleAPI.create(customRoleObj);
        this.records.push(response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.creatingItem = false;
      }
    },

    async updateCustomRole({ id, ...updateObj }) {
      this.uiFlags.updatingItem = true;
      try {
        const response = await CustomRoleAPI.update(id, updateObj);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.updatingItem = false;
      }
    },

    async deleteCustomRole(id) {
      this.uiFlags.deletingItem = true;
      try {
        await CustomRoleAPI.delete(id);
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
  import.meta.hot.accept(acceptHMRUpdate(useCustomRoleStore, import.meta.hot));
}
