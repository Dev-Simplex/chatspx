import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import NpsReports from '../../api/npsReports';
import { downloadCsvFile } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';

export const state = {
  records: [],
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
};

export const getters = {
  getNpsResponses(_state) {
    console.log('NPS Store: getNpsResponses getter called, returning:', _state.records);
    return _state.records;
  },
  getCurrentNpsResponse(_state) {
    return _state.currentResponse;
  },
  getNpsHistory(_state) {
    return _state.history;
  },
  getMetrics(_state) {
    return _state.metrics;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getResponses({ commit, state }, params) {
    commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetching: true });
    try {
      console.log('NPS Store: Fetching responses with params:', params);
      const response = await NpsReports.get(params);
      console.log('NPS Store: Responses response:', response.data);
      // Handle both old format (payload/meta) and new format (array direct)
      const data = Array.isArray(response.data) 
        ? response.data 
        : (response.data?.payload || response.data || []);
      console.log('NPS Store: Processed data:', data);
      console.log('NPS Store: Processed data length:', data.length);
      console.log('NPS Store: About to commit SET_NPS_RESPONSE');
      commit(types.SET_NPS_RESPONSE, data);
      console.log('NPS Store: After commit, state.records length:', state.records.length);
    } catch (error) {
      console.error('Error fetching NPS responses:', error);
      console.error('Error details:', error.response?.data || error.message);
      commit(types.SET_NPS_RESPONSE, []);
    } finally {
      commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetching: false });
    }
  },
  getByConversation: async function getByConversation({ commit }, { accountId, conversationId }) {
    try {
      const response = await NpsReports.getByConversation({ accountId, conversationId });
      commit(types.SET_NPS_RESPONSE_BY_CONVERSATION, response.data);
      return response.data;
    } catch (error) {
      if (error.response?.status === 404) {
        commit(types.SET_NPS_RESPONSE_BY_CONVERSATION, null);
        return null;
      }
      throw error;
    }
  },
  getByContact: async function getByContact({ commit }, { accountId, contactId }) {
    try {
      const response = await NpsReports.getByContact({ accountId, contactId });
      commit(types.SET_NPS_HISTORY, response.data || []);
      return response.data || [];
    } catch (error) {
      commit(types.SET_NPS_HISTORY, []);
      return [];
    }
  },
  sendSurvey: async function sendSurvey({ dispatch }, { accountId, conversationId }) {
    try {
      await NpsReports.sendSurvey({ accountId, conversationId });
      await dispatch('getByConversation', { accountId, conversationId });
    } catch (error) {
      throw error;
    }
  },
  getMetrics: async function getMetrics({ commit }, params) {
    commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetchingMetrics: true });
    try {
      console.log('NPS Store: Fetching metrics with params:', params);
      const response = await NpsReports.getMetrics(params);
      console.log('NPS Store: Metrics response:', response.data);
      commit(types.SET_NPS_RESPONSE_METRICS, response.data);
    } catch (error) {
      console.error('Error fetching NPS metrics:', error);
      console.error('Error details:', error.response?.data || error.message);
      // Reset metrics on error
      commit(types.SET_NPS_RESPONSE_METRICS, {
        total_count: 0,
        promoters_count: 0,
        passives_count: 0,
        detractors_count: 0,
        nps_score: 0,
        response_rate: 0,
        blocked_count: 0,
        blocked_by_label_count: {},
        scores_count: {},
      });
    } finally {
      commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetchingMetrics: false });
    }
  },
  downloadNpsReports(_, params) {
    return NpsReports.download(params).then(response => {
      downloadCsvFile(params.fileName || 'nps_report', response.data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'nps',
      });
    });
  },
};

export const mutations = {
  [types.SET_NPS_RESPONSE_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.SET_NPS_RESPONSE](_state, data) {
    console.log('NPS Store: SET_NPS_RESPONSE mutation called with data:', data);
    console.log('NPS Store: Data is array?', Array.isArray(data));
    console.log('NPS Store: Data length:', data?.length);
    // Ensure we're setting a new array reference for Vue reactivity
    _state.records = Array.isArray(data) ? [...data] : (data || []);
    console.log('NPS Store: State.records after mutation length:', _state.records.length);
    console.log('NPS Store: State.records after mutation:', _state.records);
  },
  
  [types.SET_NPS_RESPONSE_BY_CONVERSATION](_state, data) {
    _state.currentResponse = data;
  },
  
  [types.SET_NPS_HISTORY](_state, data) {
    _state.history = data;
  },
  
  [types.SET_NPS_RESPONSE_METRICS](
    _state,
    {
      total_count,
      promoters_count,
      passives_count,
      detractors_count,
      nps_score,
      response_rate,
      blocked_count,
      blocked_by_label_count,
      scores_count,
    }
  ) {
    _state.metrics.total_count = total_count || 0;
    _state.metrics.promoters_count = promoters_count || 0;
    _state.metrics.passives_count = passives_count || 0;
    _state.metrics.detractors_count = detractors_count || 0;
    _state.metrics.nps_score = nps_score || 0;
    _state.metrics.response_rate = response_rate || 0;
    _state.metrics.blocked_count = blocked_count || 0;
    _state.metrics.blocked_by_label_count = blocked_by_label_count || {};
    _state.metrics.scores_count = scores_count || {};
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
