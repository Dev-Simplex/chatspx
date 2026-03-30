/* eslint no-console: 0 */
import * as types from '../mutation-types';
import { STATUS } from '../constants';
import Report from '../../api/reports';
import { downloadCsvFile, generateFileName } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';
import { clampDataBetweenTimeline } from 'shared/helpers/ReportsDataHelper';
import liveReports from '../../api/liveReports';

const state = {
  fetchingStatus: false,
  accountSummaryFetchingStatus: STATUS.FINISHED,
  botSummaryFetchingStatus: STATUS.FINISHED,
  accountReport: {
    isFetching: {
      conversations_count: false,
      incoming_messages_count: false,
      outgoing_messages_count: false,
      avg_first_response_time: false,
      avg_first_response_time_after_assignment: false,
      avg_resolution_time: false,
      resolutions_count: false,
      bot_resolutions_count: false,
      bot_handoffs_count: false,
      reply_time: false,
    },
    data: {
      conversations_count: [],
      incoming_messages_count: [],
      outgoing_messages_count: [],
      avg_first_response_time: [],
      avg_first_response_time_after_assignment: [],
      avg_resolution_time: [],
      resolutions_count: [],
      bot_resolutions_count: [],
      bot_handoffs_count: [],
      reply_time: [],
    },
  },
  accountSummary: {
    avg_first_response_time: 0,
    avg_first_response_time_after_assignment: 0,
    avg_resolution_time: 0,
    conversations_count: 0,
    incoming_messages_count: 0,
    outgoing_messages_count: 0,
    reply_time: 0,
    resolutions_count: 0,
    bot_resolutions_count: 0,
    bot_handoffs_count: 0,
    p50_first_response_time: 0,
    p90_first_response_time: 0,
    p50_first_response_time_after_assignment: 0,
    p90_first_response_time_after_assignment: 0,
    first_response_count: 0,
    first_response_after_assignment_count: 0,
    previous: {},
  },
  botSummary: {
    bot_resolutions_count: 0,
    bot_handoffs_count: 0,
    previous: {},
  },
  overview: {
    uiFlags: {
      isFetchingAccountConversationMetric: false,
      isFetchingAccountConversationsHeatmap: false,
      isFetchingAccountResolutionsHeatmap: false,
      isFetchingAgentConversationMetric: false,
      isFetchingTeamConversationMetric: false,
    },
    accountConversationMetric: {},
    accountConversationHeatmap: [],
    accountResolutionHeatmap: [],
    agentConversationMetric: [],
    teamConversationMetric: [],
  },
};

const getters = {
  getAccountReports(_state) {
    return _state.accountReport;
  },
  getAccountSummary(_state) {
    return _state.accountSummary;
  },
  getBotSummary(_state) {
    return _state.botSummary;
  },
  getAccountSummaryFetchingStatus(_state) {
    return _state.accountSummaryFetchingStatus;
  },
  getBotSummaryFetchingStatus(_state) {
    return _state.botSummaryFetchingStatus;
  },
  getAccountConversationMetric(_state) {
    return _state.overview.accountConversationMetric;
  },
  getAccountConversationHeatmapData(_state) {
    return _state.overview.accountConversationHeatmap;
  },
  getAccountResolutionHeatmapData(_state) {
    return _state.overview.accountResolutionHeatmap;
  },
  getAgentConversationMetric(_state) {
    return _state.overview.agentConversationMetric;
  },
  getTeamConversationMetric(_state) {
    return _state.overview.teamConversationMetric;
  },
  getOverviewUIFlags($state) {
    return $state.overview.uiFlags;
  },
};

export const actions = {
  async fetchAccountReport({ commit }, reportObj) {
    const { metric } = reportObj;
    commit(types.default.TOGGLE_ACCOUNT_REPORT_LOADING, {
      metric,
      value: true,
    });
    try {
      const accountReport = await Report.getReports(reportObj);
      let { data } = accountReport;
      data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
      commit(types.default.SET_ACCOUNT_REPORTS, { metric, data });
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.default.TOGGLE_ACCOUNT_REPORT_LOADING, {
        metric,
        value: false,
      });
    }
  },
  async fetchAccountConversationHeatmap({ commit }, reportObj) {
    commit(types.default.TOGGLE_HEATMAP_LOADING, true);
    try {
      const heatmapData = await Report.getReports({
        ...reportObj,
        groupBy: 'hour',
      });
      let { data } = heatmapData;
      data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
      commit(types.default.SET_HEATMAP_DATA, data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.default.TOGGLE_HEATMAP_LOADING, false);
    }
  },
  async fetchAccountResolutionHeatmap({ commit }, reportObj) {
    commit(types.default.TOGGLE_RESOLUTION_HEATMAP_LOADING, true);
    try {
      const heatmapData = await Report.getReports({
        ...reportObj,
        groupBy: 'hour',
      });
      let { data } = heatmapData;
      data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
      commit(types.default.SET_RESOLUTION_HEATMAP_DATA, data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.default.TOGGLE_RESOLUTION_HEATMAP_LOADING, false);
    }
  },
  async fetchAccountSummary({ commit }, reportObj) {
    commit(types.default.SET_ACCOUNT_SUMMARY_STATUS, STATUS.FETCHING);
    try {
      const accountSummary = await Report.getSummary(
        reportObj.from,
        reportObj.to,
        reportObj.type,
        reportObj.id,
        reportObj.groupBy,
        reportObj.businessHours
      );
      commit(types.default.SET_ACCOUNT_SUMMARY, accountSummary.data);
      commit(types.default.SET_ACCOUNT_SUMMARY_STATUS, STATUS.FINISHED);
    } catch {
      commit(types.default.SET_ACCOUNT_SUMMARY_STATUS, STATUS.FAILED);
    }
  },
  async fetchBotSummary({ commit }, reportObj) {
    commit(types.default.SET_BOT_SUMMARY_STATUS, STATUS.FETCHING);
    try {
      const botSummary = await Report.getBotSummary({
        from: reportObj.from,
        to: reportObj.to,
        groupBy: reportObj.groupBy,
        businessHours: reportObj.businessHours,
      });
      commit(types.default.SET_BOT_SUMMARY, botSummary.data);
      commit(types.default.SET_BOT_SUMMARY_STATUS, STATUS.FINISHED);
    } catch {
      commit(types.default.SET_BOT_SUMMARY_STATUS, STATUS.FAILED);
    }
  },
  async fetchAccountConversationMetric({ commit }, params = {}) {
    commit(types.default.TOGGLE_ACCOUNT_CONVERSATION_METRIC_LOADING, true);
    try {
      const { data } = await liveReports.getConversationMetric(params);
      commit(types.default.SET_ACCOUNT_CONVERSATION_METRIC, data);
    } catch {
      // silently handle
    } finally {
      commit(types.default.TOGGLE_ACCOUNT_CONVERSATION_METRIC_LOADING, false);
    }
  },
  async fetchAgentConversationMetric({ commit }) {
    commit(types.default.TOGGLE_AGENT_CONVERSATION_METRIC_LOADING, true);
    try {
      const { data } = await liveReports.getGroupedConversations({
        groupBy: 'assignee_id',
      });
      commit(types.default.SET_AGENT_CONVERSATION_METRIC, data);
    } catch {
      // silently handle
    } finally {
      commit(types.default.TOGGLE_AGENT_CONVERSATION_METRIC_LOADING, false);
    }
  },
  async fetchTeamConversationMetric({ commit }) {
    commit(types.default.TOGGLE_TEAM_CONVERSATION_METRIC_LOADING, true);
    try {
      const { data } = await liveReports.getGroupedConversations({
        groupBy: 'team_id',
      });
      commit(types.default.SET_TEAM_CONVERSATION_METRIC, data);
    } catch {
      // silently handle
    } finally {
      commit(types.default.TOGGLE_TEAM_CONVERSATION_METRIC_LOADING, false);
    }
  },
  async downloadAgentReports(_, reportObj) {
    try {
      const { data } = await Report.getAgentReports(reportObj);
      downloadCsvFile(reportObj.fileName, data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'agent',
        businessHours: reportObj?.businessHours,
      });
    } catch (error) {
      console.error(error);
    }
  },
  async downloadConversationsSummaryReports(_, reportObj) {
    try {
      const { data } = await Report.getConversationsSummaryReports(reportObj);
      downloadCsvFile(reportObj.fileName, data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'conversations_summary',
        businessHours: reportObj?.businessHours,
      });
    } catch (error) {
      console.error(error);
    }
  },
  async downloadLabelReports(_, reportObj) {
    try {
      const { data } = await Report.getLabelReports(reportObj);
      downloadCsvFile(reportObj.fileName, data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'label',
        businessHours: reportObj?.businessHours,
      });
    } catch (error) {
      console.error(error);
    }
  },
  async downloadInboxReports(_, reportObj) {
    try {
      const { data } = await Report.getInboxReports(reportObj);
      downloadCsvFile(reportObj.fileName, data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'inbox',
        businessHours: reportObj?.businessHours,
      });
    } catch (error) {
      console.error(error);
    }
  },
  async downloadTeamReports(_, reportObj) {
    try {
      const { data } = await Report.getTeamReports(reportObj);
      downloadCsvFile(reportObj.fileName, data);
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'team',
        businessHours: reportObj?.businessHours,
      });
    } catch (error) {
      console.error(error);
    }
  },
  async downloadAccountConversationHeatmap(_, reportObj) {
    try {
      const { data } = await Report.getConversationTrafficCSV({
        daysBefore: reportObj.daysBefore,
      });
      downloadCsvFile(
        generateFileName({
          type: 'Conversation traffic',
          to: reportObj.to,
        }),
        data
      );
      AnalyticsHelper.track(REPORTS_EVENTS.DOWNLOAD_REPORT, {
        reportType: 'conversation_heatmap',
        businessHours: false,
      });
    } catch (error) {
      console.error(error);
    }
  },
};

const mutations = {
  [types.default.SET_ACCOUNT_REPORTS](_state, { metric, data }) {
    _state.accountReport.data[metric] = data;
  },
  [types.default.SET_HEATMAP_DATA](_state, heatmapData) {
    _state.overview.accountConversationHeatmap = heatmapData;
  },
  [types.default.SET_RESOLUTION_HEATMAP_DATA](_state, heatmapData) {
    _state.overview.accountResolutionHeatmap = heatmapData;
  },
  [types.default.TOGGLE_ACCOUNT_REPORT_LOADING](_state, { metric, value }) {
    _state.accountReport.isFetching[metric] = value;
  },
  [types.default.SET_BOT_SUMMARY_STATUS](_state, status) {
    _state.botSummaryFetchingStatus = status;
  },
  [types.default.SET_ACCOUNT_SUMMARY_STATUS](_state, status) {
    _state.accountSummaryFetchingStatus = status;
  },
  [types.default.TOGGLE_HEATMAP_LOADING](_state, flag) {
    _state.overview.uiFlags.isFetchingAccountConversationsHeatmap = flag;
  },
  [types.default.TOGGLE_RESOLUTION_HEATMAP_LOADING](_state, flag) {
    _state.overview.uiFlags.isFetchingAccountResolutionsHeatmap = flag;
  },
  [types.default.SET_ACCOUNT_SUMMARY](_state, summaryData) {
    _state.accountSummary = summaryData;
  },
  [types.default.SET_BOT_SUMMARY](_state, summaryData) {
    _state.botSummary = summaryData;
  },
  [types.default.SET_ACCOUNT_CONVERSATION_METRIC](_state, metricData) {
    _state.overview.accountConversationMetric = metricData;
  },
  [types.default.TOGGLE_ACCOUNT_CONVERSATION_METRIC_LOADING](_state, flag) {
    _state.overview.uiFlags.isFetchingAccountConversationMetric = flag;
  },
  [types.default.SET_AGENT_CONVERSATION_METRIC](_state, metricData) {
    _state.overview.agentConversationMetric = metricData;
  },
  [types.default.TOGGLE_AGENT_CONVERSATION_METRIC_LOADING](_state, flag) {
    _state.overview.uiFlags.isFetchingAgentConversationMetric = flag;
  },
  [types.default.SET_TEAM_CONVERSATION_METRIC](_state, metricData) {
    _state.overview.teamConversationMetric = metricData;
  },
  [types.default.TOGGLE_TEAM_CONVERSATION_METRIC_LOADING](_state, flag) {
    _state.overview.uiFlags.isFetchingTeamConversationMetric = flag;
  },
};

export default {
  state,
  getters,
  actions,
  mutations,
};
