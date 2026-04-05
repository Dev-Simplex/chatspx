<script>
import { mapGetters } from 'vuex';
import { useAlert, useTrack } from 'dashboard/composables';
import NpsMetrics from './components/NpsMetrics.vue';
import NpsTable from './components/NpsTable.vue';
import ReportFilterSelector from './components/FilterSelector.vue';
import { generateFileName } from '../../../../helper/downloadHelper';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'NetPromoterScoreReports',
  components: {
    NpsMetrics,
    NpsTable,
    ReportFilterSelector,
    ReportHeader,
    V4Button,
  },
  data() {
    return {
      pageIndex: 0,
      from: 0,
      to: 0,
      userIds: [],
      inbox: null,
      team: null,
      responseState: 'responded',
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledOnAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
        user_ids: this.userIds,
        inbox_id: this.inbox,
        team_id: this.team,
      };
    },
    isTeamsEnabled() {
      return this.isFeatureEnabledOnAccount(
        this.accountId,
        FEATURE_FLAGS.TEAM_MANAGEMENT
      );
    },
  },
  methods: {
    getAllData() {
      try {
        this.$store.dispatch('npsResponses/getMetrics', this.requestPayload);
        this.getResponses();
      } catch {
        useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
      }
    },
    getResponses() {
      this.$store.dispatch('npsResponses/get', {
        page: this.pageIndex + 1,
        response_state: this.responseState,
        ...this.requestPayload,
      });
    },
    downloadReports() {
      const type = 'nps';
      try {
        this.$store.dispatch('npsResponses/downloadNpsReports', {
          fileName: generateFileName({ type, to: this.to }),
          ...this.requestPayload,
        });
      } catch (error) {
        useAlert(
          this.$t('REPORT.NPS_REPORTS.DOWNLOAD_FAILED', {
            default: 'Erro ao baixar relatório NPS',
          })
        );
      }
    },
    onPageNumberChange(pageIndex) {
      this.pageIndex = pageIndex;
      this.getResponses();
    },
    onResponseStateChange(responseState) {
      this.responseState = responseState;
      this.pageIndex = 0;
      this.getResponses();
    },
    onFilterChange({ from, to, selectedAgents, selectedInbox, selectedTeam }) {
      // do not track filter change on initial load
      if (this.from !== 0 && this.to !== 0) {
        useTrack(REPORTS_EVENTS.FILTER_REPORT, {
          filterType: 'date',
          reportType: 'nps',
        });
      }

      this.from = from;
      this.to = to;
      this.userIds = selectedAgents.map(el => el.id);
      this.inbox = selectedInbox?.id;
      this.team = selectedTeam?.id;
      this.pageIndex = 0;

      this.getAllData();
    },
  },
};
</script>

<template>
  <ReportHeader
    :header-title="$t('NPS_REPORTS.HEADER', { default: 'Relatórios NPS' })"
  >
    <V4Button
      :label="$t('NPS_REPORTS.DOWNLOAD', { default: 'Exportar CSV' })"
      icon="i-lucide-download"
      size="sm"
      @click="downloadReports"
    />
  </ReportHeader>

  <div class="flex flex-col gap-6">
    <ReportFilterSelector
      show-agents-filter
      show-inbox-filter
      :show-team-filter="isTeamsEnabled"
      :show-business-hours-switch="false"
      @filter-change="onFilterChange"
    />

    <NpsMetrics :filters="requestPayload" />
    <NpsTable
      :page-index="pageIndex"
      :response-state="responseState"
      @page-change="onPageNumberChange"
      @response-state-change="onResponseStateChange"
    />
  </div>
</template>
