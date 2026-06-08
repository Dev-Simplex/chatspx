/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

// Espelho Pinia de store/modules/summaryReports.js (Onda 2 P0-05).
const typeMap = {
  inbox: {
    flagKey: 'isFetchingInboxSummaryReports',
    apiMethod: 'getInboxReports',
    stateKey: 'inboxSummaryReports',
  },
  agent: {
    flagKey: 'isFetchingAgentSummaryReports',
    apiMethod: 'getAgentReports',
    stateKey: 'agentSummaryReports',
  },
  team: {
    flagKey: 'isFetchingTeamSummaryReports',
    apiMethod: 'getTeamReports',
    stateKey: 'teamSummaryReports',
  },
  label: {
    flagKey: 'isFetchingLabelSummaryReports',
    apiMethod: 'getLabelReports',
    stateKey: 'labelSummaryReports',
  },
};

export const useSummaryReportsStore = defineStore('summaryReports', {
  state: () => ({
    inboxSummaryReports: [],
    agentSummaryReports: [],
    teamSummaryReports: [],
    labelSummaryReports: [],
    uiFlags: {
      isFetchingInboxSummaryReports: false,
      isFetchingAgentSummaryReports: false,
      isFetchingTeamSummaryReports: false,
      isFetchingLabelSummaryReports: false,
    },
  }),

  getters: {
    getInboxSummaryReports: state => state.inboxSummaryReports,
    getAgentSummaryReports: state => state.agentSummaryReports,
    getTeamSummaryReports: state => state.teamSummaryReports,
    getLabelSummaryReports: state => state.labelSummaryReports,
    getUIFlags: state => state.uiFlags,
  },

  actions: {
    async _fetchSummaryReports(type, params) {
      const config = typeMap[type];
      if (!config) return;
      let error = null;
      try {
        this.uiFlags[config.flagKey] = true;
        const response = await SummaryReportsAPI[config.apiMethod](params);
        this[config.stateKey] = camelcaseKeys(response.data, { deep: true });
      } catch (e) {
        error = e;
      } finally {
        this.uiFlags[config.flagKey] = false;
      }
      if (error) throw error;
    },

    fetchInboxSummaryReports(params) {
      return this._fetchSummaryReports('inbox', params);
    },

    fetchAgentSummaryReports(params) {
      return this._fetchSummaryReports('agent', params);
    },

    fetchTeamSummaryReports(params) {
      return this._fetchSummaryReports('team', params);
    },

    fetchLabelSummaryReports(params) {
      return this._fetchSummaryReports('label', params);
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useSummaryReportsStore, import.meta.hot)
  );
}
