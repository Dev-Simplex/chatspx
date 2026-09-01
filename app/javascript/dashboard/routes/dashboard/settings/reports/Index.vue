<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAlert, useTrack } from 'dashboard/composables';
import ReportFilters from './components/ReportFilters.vue';
import { GROUP_BY_FILTER } from './constants';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import ReportContainer from './ReportContainer.vue';
import ReportHeader from './components/ReportHeader.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import SpeedInsightsPanel from './components/SpeedInsightsPanel.vue';
import ReportNarrativeSummary from './components/ReportNarrativeSummary.vue';
import { mapGetters } from 'vuex';

const REPORTS_KEYS = {
  CONVERSATIONS: 'conversations_count',
  INCOMING_MESSAGES: 'incoming_messages_count',
  OUTGOING_MESSAGES: 'outgoing_messages_count',
  FIRST_RESPONSE_TIME: 'avg_first_response_time',
  FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT:
    'avg_first_response_time_after_assignment',
  RESOLUTION_TIME: 'avg_resolution_time',
  RESOLUTION_COUNT: 'resolutions_count',
  REPLY_TIME: 'reply_time',
};

export default {
  name: 'ConversationReports',
  components: {
    ReportHeader,
    ReportFilters,
    ReportContainer,
    V4Button,
    DownloadPdfButton,
    SpeedInsightsPanel,
    ReportNarrativeSummary,
  },
  data() {
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      businessHours: false,
      inboxId: null,
    };
  },
  computed: {
    ...mapGetters({
      accountSummary: 'getAccountSummary',
    }),
  },
  methods: {
    fetchAllData() {
      this.fetchAccountSummary();
      this.fetchChartData();
    },
    fetchAccountSummary() {
      try {
        this.$store.dispatch('fetchAccountSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      [
        'CONVERSATIONS',
        'INCOMING_MESSAGES',
        'OUTGOING_MESSAGES',
        'FIRST_RESPONSE_TIME',
        'FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT',
        'RESOLUTION_TIME',
        'RESOLUTION_COUNT',
        'REPLY_TIME',
      ].forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: REPORTS_KEYS[key],
            ...this.getRequestPayload(),
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    getRequestPayload() {
      const { from, to, groupBy, businessHours, inboxId } = this;

      return {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
        inboxId,
      };
    },
    downloadConversationReports() {
      const { from, to } = this;
      const fileName = generateFileName({
        type: 'conversation',
        to,
        businessHours: this.businessHours,
      });
      this.$store.dispatch('downloadConversationsSummaryReports', {
        from,
        to,
        fileName,
        businessHours: this.businessHours,
        inboxId: this.inboxId,
      });
    },
    onFilterChange({ from, to, groupBy, businessHours, inboxId }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      this.inboxId = inboxId || null;
      this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: { from, to, groupBy, businessHours },
        reportType: 'conversations',
      });
    },
  },
};
</script>

<template>
  <ReportHeader
    :header-title="$t('REPORT.HEADER')"
    :header-description="$t('REPORT.DESCRIPTION')"
  >
    <div class="flex items-center gap-2">
      <DownloadPdfButton
        report-type="conversations"
        :filters="{
          from,
          to,
          business_hours: businessHours,
          inbox_id: inboxId,
        }"
      />
      <V4Button
        :label="$t('REPORT.DOWNLOAD_CONVERSATION_REPORTS')"
        icon="i-lucide-download"
        size="sm"
        @click="downloadConversationReports"
      />
    </div>
  </ReportHeader>
  <div class="flex flex-col">
    <ReportFilters
      :show-entity-filter="false"
      show-group-by
      @filter-change="onFilterChange"
    />
    <ReportNarrativeSummary :signals="accountSummary.signals || []" />
    <SpeedInsightsPanel />
    <ReportContainer :group-by="groupBy" />
  </div>
</template>
