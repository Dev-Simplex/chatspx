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
    total_sent_count: 0,
    promoters_count: 0,
    passives_count: 0,
    detractors_count: 0,
    promoters_pct: 0,
    passives_pct: 0,
    detractors_pct: 0,
    nps_score: 0,
    response_rate: 0,
    reliable: true,
    min_sample: 30,
    previous_nps_score: null,
    nps_delta: null,
    blocked_count: 0,
    blocked_by_label_count: {},
    scores_count: {},
    signals: [],
    detractor_followup: {
      total: 0,
      followed_up_count: 0,
      awaiting_count: 0,
      avg_followup_seconds: null,
      scan_truncated: false,
    },
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

  [types.SET_NPS_RESPONSE_METRICS](_state, payload = {}) {
    const data = payload || {};
    _state.metrics = {
      total_count: data.total_count || 0,
      total_sent_count: data.total_sent_count || 0,
      promoters_count: data.promoters_count || 0,
      passives_count: data.passives_count || 0,
      detractors_count: data.detractors_count || 0,
      promoters_pct: data.promoters_pct || 0,
      passives_pct: data.passives_pct || 0,
      detractors_pct: data.detractors_pct || 0,
      nps_score: data.nps_score || 0,
      response_rate: data.response_rate || 0,
      // reliable ausente no payload = assume confiável (não penaliza contas legadas)
      reliable: data.reliable !== false,
      min_sample: data.min_sample || 30,
      previous_nps_score:
        data.previous_nps_score === undefined ? null : data.previous_nps_score,
      nps_delta: data.nps_delta === undefined ? null : data.nps_delta,
      blocked_count: data.blocked_count || 0,
      blocked_by_label_count: data.blocked_by_label_count || {},
      scores_count: data.scores_count || {},
      signals: data.signals || [],
      detractor_followup: {
        total: data.detractor_followup?.total || 0,
        followed_up_count: data.detractor_followup?.followed_up_count || 0,
        awaiting_count: data.detractor_followup?.awaiting_count || 0,
        avg_followup_seconds:
          data.detractor_followup?.avg_followup_seconds ?? null,
        scan_truncated: data.detractor_followup?.scan_truncated || false,
      },
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
