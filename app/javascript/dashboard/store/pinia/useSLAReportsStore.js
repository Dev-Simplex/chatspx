import { defineStore, acceptHMRUpdate } from 'pinia';
import SLAReportsAPI from '../../api/slaReports';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

// Espelho Pinia de store/modules/SLAReports.js (Onda 2 P0-05).
export const useSLAReportsStore = defineStore('SLAReports', {
  state: () => ({
    records: [],
    metrics: {
      numberOfConversations: 0,
      numberOfSLAMisses: 0,
      hitRate: '0%',
    },
    uiFlags: {
      isFetching: false,
      isFetchingMetrics: false,
    },
    meta: { count: 0, currentPage: 1 },
  }),

  getters: {
    getAll: state => state.records,
    getMeta: state => state.meta,
    getMetrics: state => state.metrics,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async get(params) {
      this.uiFlags.isFetching = true;
      try {
        const response = await SLAReportsAPI.get(params);
        const { payload, meta } = response.data;
        this.records = payload;
        this.meta = { count: meta.count, currentPage: meta.current_page };
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async getMetrics(params) {
      this.uiFlags.isFetchingMetrics = true;
      try {
        const response = await SLAReportsAPI.getMetrics(params);
        const {
          number_of_sla_misses: numberOfSLAMisses,
          hit_rate: hitRate,
          total_applied_slas: numberOfConversations,
        } = response.data;
        this.metrics = { numberOfSLAMisses, hitRate, numberOfConversations };
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingMetrics = false;
      }
    },

    async download(params) {
      const response = await SLAReportsAPI.download(params);
      downloadCsvFile(params.fileName, response.data);
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useSLAReportsStore, import.meta.hot));
}
