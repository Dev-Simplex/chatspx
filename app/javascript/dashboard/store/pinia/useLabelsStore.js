import { defineStore, acceptHMRUpdate } from 'pinia';
import LabelsAPI from '../../api/labels';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { LABEL_EVENTS } from '../../helper/AnalyticsHelper/events';

// Espelho Pinia de store/modules/labels.js (Onda 1 P0-05).
// Coexiste com o Vuex; consumidores Vue continuam usando Vuex ate migracao em P1+.
export const useLabelsStore = defineStore('labels', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isDeleting: false,
      isUpdating: false,
    },
  }),

  getters: {
    getLabels: state => state.records,
    getUIFlags: state => state.uiFlags,
    getLabelsOnSidebar: state =>
      state.records
        .filter(record => record.show_on_sidebar)
        .sort((a, b) => a.title.localeCompare(b.title)),
    getLabelById: state => id =>
      state.records.find(record => record.id === Number(id)) || {},
  },

  actions: {
    async revalidate({ newKey }) {
      try {
        const isExistingKeyValid = await LabelsAPI.validateCacheKey(newKey);
        if (!isExistingKeyValid) {
          const response = await LabelsAPI.refetchAndCommit(newKey);
          this.records = response.data.payload;
        }
      } catch (error) {
        // Ignore error
      }
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await LabelsAPI.get(true);
        this.records = response.data.payload.sort((a, b) =>
          a.title.localeCompare(b.title)
        );
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(payload) {
      this.uiFlags.isCreating = true;
      try {
        const response = await LabelsAPI.create(payload);
        AnalyticsHelper.track(LABEL_EVENTS.CREATE);
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
        const response = await LabelsAPI.update(id, updateObj);
        AnalyticsHelper.track(LABEL_EVENTS.UPDATE);
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
        await LabelsAPI.delete(id);
        AnalyticsHelper.track(LABEL_EVENTS.DELETED);
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
  import.meta.hot.accept(acceptHMRUpdate(useLabelsStore, import.meta.hot));
}
