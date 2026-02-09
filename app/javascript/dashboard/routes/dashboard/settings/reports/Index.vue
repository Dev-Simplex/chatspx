<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAlert, useTrack } from 'dashboard/composables';
import ReportFilterSelector from './components/FilterSelector.vue';
import { GROUP_BY_FILTER } from './constants';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import ReportContainer from './ReportContainer.vue';
import ReportsHero from './components/ReportsHero.vue';
import ReportsShell from './components/ReportsShell.vue';
import SpeedInsightsPanel from './components/SpeedInsightsPanel.vue';

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
    ReportsHero,
    ReportsShell,
    ReportFilterSelector,
    ReportContainer,
    V4Button,
    SpeedInsightsPanel,
  },
  data() {
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      businessHours: false,
    };
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
      const { from, to, groupBy, businessHours } = this;

      return {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
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
      });
    },
    onFilterChange({ from, to, groupBy, businessHours }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
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
  <ReportsShell>
    <template #filters>
      <ReportFilterSelector
        layout="rail"
        :show-agents-filter="false"
        show-group-by-filter
        @filter-change="onFilterChange"
      />
    </template>
    <template #content>
      <ReportsHero
        :title="$t('REPORT.HEADER')"
        :description="$t('REPORT.DESCRIPTION')"
      >
        <template #actions>
          <V4Button
            :label="$t('REPORT.DOWNLOAD_CONVERSATION_REPORTS')"
            icon="i-ph-download-simple"
            size="sm"
            @click="downloadConversationReports"
          />
        </template>
      </ReportsHero>
      <div class="flex flex-col gap-6 pb-6">
        <SpeedInsightsPanel />
        <ReportContainer :group-by="groupBy" />
      </div>
    </template>
  </ReportsShell>
</template>
