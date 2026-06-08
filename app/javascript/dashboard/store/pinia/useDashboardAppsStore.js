import { defineStore, acceptHMRUpdate } from 'pinia';
import DashboardAppsAPI from '../../api/dashboardApps';

// Espelho Pinia de store/modules/dashboardApps.js (Onda 2 P0-05).
export const useDashboardAppsStore = defineStore('dashboardApps', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getRecords: state => state.records,
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await DashboardAppsAPI.get();
        this.records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(appObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await DashboardAppsAPI.create(appObj);
        this.records.push(response.data);
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await DashboardAppsAPI.update(id, updateObj);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await DashboardAppsAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
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
    acceptHMRUpdate(useDashboardAppsStore, import.meta.hot)
  );
}
