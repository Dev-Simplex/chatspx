import types from '../mutation-types';
import NpsReports from '../../api/npsReports';
import { downloadCsvFile } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';

export const state = {
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
    signals: [],
  },
  uiFlags: {
    isFetching: false,
    isFetchingMetrics: false,
  },
};

export const getters = {
  getNpsResponses(_state) {
    return _state.records;
  },
  getNpsListTotalCount(_state) {
    return _state.listTotalCount;
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
  get: async function getResponses({ commit }, params) {
    commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetching: true });
    try {
      const response = await NpsReports.get(params);
      const data = Array.isArray(response.data)
        ? response.data
        : response.data?.payload || response.data || [];
      commit(types.SET_NPS_RESPONSE, data);
      const totalCount = parseInt(response.headers?.['x-total-count'], 10);
      commit(
        types.SET_NPS_LIST_TOTAL_COUNT,
        Number.isFinite(totalCount) ? totalCount : 0
      );
    } catch (error) {
      commit(types.SET_NPS_RESPONSE, []);
      commit(types.SET_NPS_LIST_TOTAL_COUNT, 0);
    } finally {
      commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetching: false });
    }
  },
  getByConversation: async function getByConversation(
    { commit },
    { accountId, conversationId }
  ) {
    try {
      const response = await NpsReports.getByConversation({
        accountId,
        conversationId,
      });
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
  getByContact: async function getByContact(
    { commit },
    { accountId, contactId }
  ) {
    try {
      const response = await NpsReports.getByContact({ accountId, contactId });
      commit(types.SET_NPS_HISTORY, response.data || []);
      return response.data || [];
    } catch (error) {
      commit(types.SET_NPS_HISTORY, []);
      return [];
    }
  },
  sendSurvey: async function sendSurvey(
    { dispatch },
    { accountId, conversationId }
  ) {
    await NpsReports.sendSurvey({ accountId, conversationId });
    await dispatch('getByConversation', { accountId, conversationId });
  },
  getMetrics: async function getMetrics({ commit }, params) {
    commit(types.SET_NPS_RESPONSE_UI_FLAG, { isFetchingMetrics: true });
    try {
      const response = await NpsReports.getMetrics(params);
      commit(types.SET_NPS_RESPONSE_METRICS, response.data);
    } catch (error) {
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
    _state.records = Array.isArray(data) ? [...data] : data || [];
  },

  [types.SET_NPS_LIST_TOTAL_COUNT](_state, count) {
    _state.listTotalCount = count;
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
      signals,
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
    _state.metrics.signals = signals || [];
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
