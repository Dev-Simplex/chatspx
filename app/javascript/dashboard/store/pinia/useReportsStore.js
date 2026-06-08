/* eslint no-console: 0 */
import { defineStore, acceptHMRUpdate } from 'pinia';
import { clampDataBetweenTimeline } from 'shared/helpers/ReportsDataHelper';
import { STATUS } from '../constants';
import Report from '../../api/reports';
import liveReports from '../../api/liveReports';
import { downloadCsvFile, generateFileName } from '../../helper/downloadHelper';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { REPORTS_EVENTS } from '../../helper/AnalyticsHelper/events';

// Espelho Pinia de store/modules/reports.js (Onda 2 P0-05).
export const useReportsStore = defineStore('reports', {
  state: () => ({
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
  }),

  getters: {
    getAccountReports: state => state.accountReport,
    getAccountSummary: state => state.accountSummary,
    getBotSummary: state => state.botSummary,
    getAccountSummaryFetchingStatus: state =>
      state.accountSummaryFetchingStatus,
    getBotSummaryFetchingStatus: state => state.botSummaryFetchingStatus,
    getAccountConversationMetric: state =>
      state.overview.accountConversationMetric,
    getAccountConversationHeatmapData: state =>
      state.overview.accountConversationHeatmap,
    getAccountResolutionHeatmapData: state =>
      state.overview.accountResolutionHeatmap,
    getAgentConversationMetric: state => state.overview.agentConversationMetric,
    getTeamConversationMetric: state => state.overview.teamConversationMetric,
    getOverviewUIFlags: state => state.overview.uiFlags,
  },

  actions: {
    async fetchAccountReport(reportObj) {
      const { metric } = reportObj;
      this.accountReport.isFetching[metric] = true;
      try {
        const accountReport = await Report.getReports(reportObj);
        let { data } = accountReport;
        data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
        this.accountReport.data[metric] = data;
      } catch (error) {
        // Ignore error
      } finally {
        this.accountReport.isFetching[metric] = false;
      }
    },

    async fetchAccountConversationHeatmap(reportObj) {
      this.overview.uiFlags.isFetchingAccountConversationsHeatmap = true;
      try {
        const heatmap = await Report.getReports({
          ...reportObj,
          groupBy: 'hour',
        });
        let { data } = heatmap;
        data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
        this.overview.accountConversationHeatmap = data;
      } catch (error) {
        // Ignore error
      } finally {
        this.overview.uiFlags.isFetchingAccountConversationsHeatmap = false;
      }
    },

    async fetchAccountResolutionHeatmap(reportObj) {
      this.overview.uiFlags.isFetchingAccountResolutionsHeatmap = true;
      try {
        const heatmap = await Report.getReports({
          ...reportObj,
          groupBy: 'hour',
        });
        let { data } = heatmap;
        data = clampDataBetweenTimeline(data, reportObj.from, reportObj.to);
        this.overview.accountResolutionHeatmap = data;
      } catch (error) {
        // Ignore error
      } finally {
        this.overview.uiFlags.isFetchingAccountResolutionsHeatmap = false;
      }
    },

    async fetchAccountSummary(reportObj) {
      this.accountSummaryFetchingStatus = STATUS.FETCHING;
      try {
        const summary = await Report.getSummary(
          reportObj.from,
          reportObj.to,
          reportObj.type,
          reportObj.id,
          reportObj.groupBy,
          reportObj.businessHours
        );
        this.accountSummary = summary.data;
        this.accountSummaryFetchingStatus = STATUS.FINISHED;
      } catch {
        this.accountSummaryFetchingStatus = STATUS.FAILED;
      }
    },

    async fetchBotSummary(reportObj) {
      this.botSummaryFetchingStatus = STATUS.FETCHING;
      try {
        const summary = await Report.getBotSummary({
          from: reportObj.from,
          to: reportObj.to,
          groupBy: reportObj.groupBy,
          businessHours: reportObj.businessHours,
        });
        this.botSummary = summary.data;
        this.botSummaryFetchingStatus = STATUS.FINISHED;
      } catch {
        this.botSummaryFetchingStatus = STATUS.FAILED;
      }
    },

    async fetchAccountConversationMetric(params = {}) {
      this.overview.uiFlags.isFetchingAccountConversationMetric = true;
      try {
        const { data } = await liveReports.getConversationMetric(params);
        this.overview.accountConversationMetric = data;
      } catch {
        // silently
      } finally {
        this.overview.uiFlags.isFetchingAccountConversationMetric = false;
      }
    },

    async fetchAgentConversationMetric() {
      this.overview.uiFlags.isFetchingAgentConversationMetric = true;
      try {
        const { data } = await liveReports.getGroupedConversations({
          groupBy: 'assignee_id',
        });
        this.overview.agentConversationMetric = data;
      } catch {
        // silently
      } finally {
        this.overview.uiFlags.isFetchingAgentConversationMetric = false;
      }
    },

    async fetchTeamConversationMetric() {
      this.overview.uiFlags.isFetchingTeamConversationMetric = true;
      try {
        const { data } = await liveReports.getGroupedConversations({
          groupBy: 'team_id',
        });
        this.overview.teamConversationMetric = data;
      } catch {
        // silently
      } finally {
        this.overview.uiFlags.isFetchingTeamConversationMetric = false;
      }
    },

    async downloadAgentReports(reportObj) {
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

    async downloadConversationsSummaryReports(reportObj) {
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

    async downloadLabelReports(reportObj) {
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

    async downloadInboxReports(reportObj) {
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

    async downloadTeamReports(reportObj) {
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

    async downloadAccountConversationHeatmap(reportObj) {
      try {
        const { data } = await Report.getConversationTrafficCSV({
          daysBefore: reportObj.daysBefore,
        });
        downloadCsvFile(
          generateFileName({ type: 'Conversation traffic', to: reportObj.to }),
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
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useReportsStore, import.meta.hot));
}
