import { defineStore, acceptHMRUpdate } from 'pinia';
import NpsReports from '../../api/npsReports';
import { downloadCsvFile } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';

// Espelho Pinia de store/modules/npsResponses.js (Onda 2 P0-05).
export const useNpsResponsesStore = defineStore('npsResponses', {
  state: () => ({
    records: [],
    listTotalCount: 0,
    currentResponse: null,
    history: [],
    metrics: {
      total_count: 0,
      promoters_count: 0,
      passives_count: 0,
      detractors_count: 0,
      nps_score: 0,
      response_rate: 0,
      blocked_count: 0,
      blocked_by_label_count: {},
      scores_count: {},
    },
    uiFlags: {
      isFetching: false,
      isFetchingMetrics: false,
    },
  }),

  getters: {
    getNpsResponses: state => state.records,
    getNpsListTotalCount: state => state.listTotalCount,
    getCurrentNpsResponse: state => state.currentResponse,
    getNpsHistory: state => state.history,
    getMetrics: state => state.metrics,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async get(params) {
      this.uiFlags.isFetching = true;
      try {
        const response = await NpsReports.get(params);
        const data = Array.isArray(response.data)
          ? response.data
          : response.data?.payload || response.data || [];
        this.records = Array.isArray(data) ? [...data] : data || [];
        const totalCount = parseInt(response.headers?.['x-total-count'], 10);
        this.listTotalCount = Number.isFinite(totalCount) ? totalCount : 0;
      } catch (error) {
        this.records = [];
        this.listTotalCount = 0;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async getByConversation({ accountId, conversationId }) {
      try {
        const response = await NpsReports.getByConversation({
          accountId,
          conversationId,
        });
        this.currentResponse = response.data;
        return response.data;
      } catch (error) {
        if (error.response?.status === 404) {
          this.currentResponse = null;
          return null;
        }
        throw error;
      }
    },

    async getByContact({ accountId, contactId }) {
      try {
        const response = await NpsReports.getByContact({
          accountId,
          contactId,
        });
        this.history = response.data || [];
        return response.data || [];
      } catch (error) {
        this.history = [];
        return [];
      }
    },

    async sendSurvey({ accountId, conversationId }) {
      await NpsReports.sendSurvey({ accountId, conversationId });
      await this.getByConversation({ accountId, conversationId });
    },

    async getMetrics(params) {
      this.uiFlags.isFetchingMetrics = true;
      try {
        const response = await NpsReports.getMetrics(params);
        const m = response.data || {};
        this.metrics.total_count = m.total_count || 0;
        this.metrics.promoters_count = m.promoters_count || 0;
        this.metrics.passives_count = m.passives_count || 0;
        this.metrics.detractors_count = m.detractors_count || 0;
        this.metrics.nps_score = m.nps_score || 0;
        this.metrics.response_rate = m.response_rate || 0;
        this.metrics.blocked_count = m.blocked_count || 0;
        this.metrics.blocked_by_label_count = m.blocked_by_label_count || {};
        this.metrics.scores_count = m.scores_count || {};
      } catch (error) {
        this.metrics = {
          total_count: 0,
          promoters_count: 0,
          passives_count: 0,
          detractors_count: 0,
          nps_score: 0,
          response_rate: 0,
          blocked_count: 0,
          blocked_by_label_count: {},
          scores_count: {},
        };
      } finally {
        this.uiFlags.isFetchingMetrics = false;
      }
    },

    async downloadNpsReports(params) {
      const response = await NpsReports.download(params);
      downloadCsvFile(params.fileName || 'nps_report', response.data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'nps',
      });
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useNpsResponsesStore, import.meta.hot)
  );
}
