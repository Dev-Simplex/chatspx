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
import ReportsHero from './components/ReportsHero.vue';
import ReportsShell from './components/ReportsShell.vue';

export default {
  name: 'NetPromoterScoreReports',
  components: {
    NpsMetrics,
    NpsTable,
    ReportFilterSelector,
    ReportsHero,
    ReportsShell,
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
        useAlert(this.$t('REPORT.NPS_REPORTS.DOWNLOAD_FAILED', { default: 'Erro ao baixar relatório NPS' }));
      }
    },
    onPageNumberChange(pageIndex) {
      this.pageIndex = pageIndex;
      this.getResponses();
    },
    onFilterChange({
      from,
      to,
      selectedAgents,
      selectedInbox,
      selectedTeam,
    }) {
      console.log('NPS Reports: Filter change received', { from, to, selectedAgents, selectedInbox, selectedTeam });
      
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

      console.log('NPS Reports: Calling getAllData with payload:', this.requestPayload);
      this.getAllData();
    },
  },
};
</script>

<template>
  <ReportsShell>
    <template #filters>
      <ReportFilterSelector
        layout="rail"
        show-agents-filter
        show-inbox-filter
        :show-team-filter="isTeamsEnabled"
        :show-business-hours-switch="false"
        @filter-change="onFilterChange"
      />
    </template>
    <template #content>
      <ReportsHero
        :title="$t('NPS_REPORTS.HEADER', { default: 'Relatórios NPS' })"
      >
        <template #actions>
          <V4Button
            :label="$t('NPS_REPORTS.DOWNLOAD', { default: 'Exportar CSV' })"
            icon="i-ph-download-simple"
            size="sm"
            @click="downloadReports"
          />
        </template>
      </ReportsHero>

      <div class="flex flex-col gap-6 pb-6">
        <NpsMetrics :filters="requestPayload" />
        <NpsTable :page-index="pageIndex" @page-change="onPageNumberChange" />
      </div>
    </template>
  </ReportsShell>
</template>
