import { defineStore, acceptHMRUpdate } from 'pinia';
import SlaAPI from '../../api/sla';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { SLA_EVENTS } from '../../helper/AnalyticsHelper/events';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/sla.js (Onda 2 P0-05).
export const useSlaStore = defineStore('sla', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getSLA: state => state.records,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await SlaAPI.get();
        this.records = response.data.payload;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(slaObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await SlaAPI.create(slaObj);
        AnalyticsHelper.track(SLA_EVENTS.CREATE);
        this.records.push(response.data.payload);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await SlaAPI.delete(id);
        AnalyticsHelper.track(SLA_EVENTS.DELETED);
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
  import.meta.hot.accept(acceptHMRUpdate(useSlaStore, import.meta.hot));
}
