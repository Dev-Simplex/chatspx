import { defineStore, acceptHMRUpdate } from 'pinia';
import CSATReports from '../../api/csatReports';
import { downloadCsvFile } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';

// Espelho Pinia de store/modules/csat.js (Onda 2 P0-05).
const computeDistribution = (value, total) =>
  ((value * 100) / total).toFixed(2);

export const useCsatStore = defineStore('csat', {
  state: () => ({
    records: [],
    metrics: {
      totalResponseCount: 0,
      ratingsCount: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 },
      totalSentMessagesCount: 0,
    },
    uiFlags: {
      isFetching: false,
      isFetchingMetrics: false,
    },
  }),

  getters: {
    getCSATResponses: state => state.records,
    getMetrics: state => state.metrics,
    getUIFlags: state => state.uiFlags,
    getSatisfactionScore: state => {
      if (!state.metrics.totalResponseCount) return 0;
      return computeDistribution(
        state.metrics.ratingsCount[4] + state.metrics.ratingsCount[5],
        state.metrics.totalResponseCount
      );
    },
    getResponseRate: state => {
      if (!state.metrics.totalSentMessagesCount) return 0;
      return computeDistribution(
        state.metrics.totalResponseCount,
        state.metrics.totalSentMessagesCount
      );
    },
    getRatingPercentage: state => {
      if (!state.metrics.totalResponseCount) {
        return { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
      }
      const total = state.metrics.totalResponseCount;
      return {
        1: computeDistribution(state.metrics.ratingsCount[1], total),
        2: computeDistribution(state.metrics.ratingsCount[2], total),
        3: computeDistribution(state.metrics.ratingsCount[3], total),
        4: computeDistribution(state.metrics.ratingsCount[4], total),
        5: computeDistribution(state.metrics.ratingsCount[5], total),
      };
    },
    getRatingCount: state => state.metrics.ratingsCount,
  },

  actions: {
    async get(params) {
      this.uiFlags.isFetching = true;
      try {
        const response = await CSATReports.get(params);
        this.records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async getMetrics(params) {
      this.uiFlags.isFetchingMetrics = true;
      try {
        const response = await CSATReports.getMetrics(params);
        const {
          total_count: totalResponseCount,
          ratings_count: ratingsCount,
          total_sent_messages_count: totalSentMessagesCount,
        } = response.data;
        this.metrics.totalResponseCount = totalResponseCount || 0;
        this.metrics.ratingsCount = {
          1: ratingsCount?.['1'] || 0,
          2: ratingsCount?.['2'] || 0,
          3: ratingsCount?.['3'] || 0,
          4: ratingsCount?.['4'] || 0,
          5: ratingsCount?.['5'] || 0,
        };
        this.metrics.totalSentMessagesCount = totalSentMessagesCount || 0;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingMetrics = false;
      }
    },

    async downloadCSATReports(params) {
      const response = await CSATReports.download(params);
      downloadCsvFile(params.fileName, response.data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'csat',
      });
    },

    async update({ id, reviewNotes }) {
      const response = await CSATReports.update(id, {
        csat_review_notes: reviewNotes,
      });
      const index = this.records.findIndex(r => r.id === response.data.id);
      if (index > -1) this.records.splice(index, 1, response.data);
      return response.data;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useCsatStore, import.meta.hot));
}
