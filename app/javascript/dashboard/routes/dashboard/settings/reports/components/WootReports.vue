<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import ReportFilters from './ReportFilters.vue';
import ReportContainer from '../ReportContainer.vue';
import { GROUP_BY_FILTER } from '../constants';
import { generateFileName } from '../../../../../helper/downloadHelper';
import ReportHeader from './ReportHeader.vue';
import ReportVerdict from 'dashboard/components-next/reports/ui/ReportVerdict.vue';
import SpeedInsightsPanel from './SpeedInsightsPanel.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import ReportPlainSummary from 'dashboard/components-next/reports/ReportPlainSummary.vue';

export default {
  components: {
    ReportHeader,
    ReportVerdict,
    V4Button,
    DownloadPdfButton,
    ReportFilters,
    ReportContainer,
    SpeedInsightsPanel,
    ReportPlainSummary,
  },
  props: {
    type: {
      type: String,
      default: 'account',
    },
    getterKey: {
      type: String,
      default: '',
    },
    actionKey: {
      type: String,
      default: '',
    },
    downloadButtonLabel: {
      type: String,
      default: 'Download Reports',
    },
    reportTitle: {
      type: String,
      default: 'Download Reports',
    },
    hasBackButton: {
      type: Boolean,
      default: false,
    },
    selectedItem: {
      type: Object,
      default: null,
    },
  },
  data() {
    return {
      from: 0,
      to: 0,
      selectedFilter: this.selectedItem,
      groupBy: GROUP_BY_FILTER[1],
      businessHours: false,
      inboxId: null,
    };
  },
  computed: {
    // os mesmos signals do resumo do periodo (store getAccountSummary)
    verdictSignals() {
      return this.$store.getters.getAccountSummary?.signals || [];
    },
    // Os mesmos filtros da tela, com a entidade: cada numero abre as conversas dela (ReportDrilldownPanel).
    drilldownFilters() {
      if (!this.selectedFilter?.id) return null;
      const { from, to, businessHours, inboxId } = this;
      return {
        from,
        to,
        type: this.type,
        id: this.selectedFilter.id,
        businessHours,
        inboxId,
      };
    },
    filterType() {
      const pluralMap = {
        agent: 'agents',
        team: 'teams',
        inbox: 'inboxes',
        label: 'labels',
      };
      return pluralMap[this.type] || this.type;
    },
    filterItemsList() {
      return this.$store.getters[this.getterKey] || [];
    },
    isAgentType() {
      return this.type === 'agent';
    },
    showTransferMetric() {
      return this.type !== 'label';
    },
    headerDescription() {
      const descriptions = {
        agent: this.$t('AGENT_REPORTS.DESCRIPTION'),
        label: this.$t('LABEL_REPORTS.DESCRIPTION'),
        inbox: this.$t('INBOX_REPORTS.DESCRIPTION'),
        team: this.$t('TEAM_REPORTS.DESCRIPTION'),
      };
      return descriptions[this.type] || '';
    },
    reportKeys() {
      return {
        CONVERSATIONS: 'conversations_count',
        ...(!this.isAgentType && {
          INCOMING_MESSAGES: 'incoming_messages_count',
        }),
        OUTGOING_MESSAGES: 'outgoing_messages_count',
        FIRST_RESPONSE_TIME: 'avg_first_response_time',
        ...(this.showTransferMetric && {
          FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT:
            'avg_first_response_time_after_assignment',
        }),
        RESOLUTION_TIME: 'avg_resolution_time',
        RESOLUTION_COUNT: 'resolutions_count',
        REPLY_TIME: 'reply_time',
      };
    },
  },
  mounted() {
    this.$store.dispatch(this.actionKey);
  },
  methods: {
    fetchAllData() {
      if (this.selectedFilter) {
        const { from, to, groupBy, businessHours, inboxId } = this;
        this.$store.dispatch('fetchAccountSummary', {
          from,
          to,
          type: this.type,
          id: this.selectedFilter.id,
          groupBy: groupBy.period,
          businessHours,
          inboxId,
        });
        this.fetchChartData();
      }
    },
    fetchChartData() {
      Object.keys(this.reportKeys).forEach(async key => {
        try {
          const { from, to, groupBy, businessHours, inboxId } = this;
          this.$store.dispatch('fetchAccountReport', {
            metric: this.reportKeys[key],
            from,
            to,
            type: this.type,
            id: this.selectedFilter.id,
            groupBy: groupBy.period,
            businessHours,
            inboxId,
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    downloadReports() {
      const { from, to, type, businessHours, inboxId } = this;
      const dispatchMethods = {
        agent: 'downloadAgentReports',
        label: 'downloadLabelReports',
        inbox: 'downloadInboxReports',
        team: 'downloadTeamReports',
      };
      if (dispatchMethods[type]) {
        const fileName = generateFileName({ type, to, businessHours });
        const params = { from, to, fileName, businessHours, inboxId };
        this.$store.dispatch(dispatchMethods[type], params);
      }
    },
    onFilterChange(payload) {
      const { from, to, businessHours, groupBy, inboxId } = payload;
      this.from = from;
      this.to = to;
      this.businessHours = businessHours;
      this.inboxId = inboxId || null;

      if (groupBy) {
        this.groupBy = groupBy;
      } else {
        this.groupBy = GROUP_BY_FILTER[1];
      }

      // Get filter value directly from filterType key
      const filterValue = payload[this.filterType];
      if (filterValue) {
        this.selectedFilter = Array.isArray(filterValue)
          ? filterValue[0]
          : filterValue;
      } else {
        this.selectedFilter = null;
      }

      this.fetchAllData();
    },
  },
};
</script>

<template>
  <ReportHeader
    :header-title="reportTitle"
    :header-description="headerDescription"
    :has-back-button="hasBackButton"
  >
    <div class="flex items-center gap-2">
      <DownloadPdfButton
        :report-type="type"
        :filters="{
          from,
          to,
          business_hours: businessHours,
          inbox_id: inboxId,
        }"
      />
      <V4Button
        :label="downloadButtonLabel"
        icon="i-lucide-download"
        size="sm"
        @click="downloadReports"
      />
    </div>
    <template #filters>
      <ReportFilters
        v-if="filterItemsList"
        :filter-type="filterType"
        :selected-item="selectedFilter"
        @filter-change="onFilterChange"
      />
    </template>
  </ReportHeader>
  <ReportVerdict v-if="verdictSignals.length" :signals="verdictSignals" />

  <ReportPlainSummary :drilldown-filters="drilldownFilters" />
  <SpeedInsightsPanel
    v-if="type !== 'label'"
    :show-transfer-metrics="showTransferMetric"
  />
  <ReportContainer
    v-if="filterItemsList.length"
    :group-by="groupBy"
    :report-keys="reportKeys"
    :drilldown-filters="drilldownFilters"
  />
</template>
