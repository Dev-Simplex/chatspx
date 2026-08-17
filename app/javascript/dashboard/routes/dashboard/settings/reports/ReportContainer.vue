<script>
import { mapGetters } from 'vuex';
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import { GROUP_BY_FILTER, METRIC_CHART } from './constants';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { formatTime } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import ChartStats from './components/ChartElements/ChartStats.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportDrilldownDrawer from './components/ReportDrilldownDrawer.vue';

export default {
  components: { ChartStats, BarChart, ReportDrilldownDrawer },
  props: {
    groupBy: {
      type: Object,
      default: () => ({}),
    },
    from: {
      type: Number,
      default: 0,
    },
    to: {
      type: Number,
      default: 0,
    },
    reportType: {
      type: String,
      default: 'account',
    },
    selectedItemId: {
      type: [String, Number],
      default: null,
    },
    businessHours: {
      type: Boolean,
      default: false,
    },
    accountSummaryKey: {
      type: String,
      default: 'getAccountSummary',
    },
    summaryFetchingKey: {
      type: String,
      default: 'getAccountSummaryFetchingStatus',
    },
    reportKeys: {
      type: Object,
      default: () => ({
        CONVERSATIONS: 'conversations_count',
        INCOMING_MESSAGES: 'incoming_messages_count',
        OUTGOING_MESSAGES: 'outgoing_messages_count',
        FIRST_RESPONSE_TIME: 'avg_first_response_time',
        FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT:
          'avg_first_response_time_after_assignment',
        RESOLUTION_TIME: 'avg_resolution_time',
        RESOLUTION_COUNT: 'resolutions_count',
        REPLY_TIME: 'reply_time',
      }),
    },
  },
  setup(props) {
    const { calculateTrend, isAverageMetricType } = useReportMetrics(
      props.accountSummaryKey
    );
    const { signalForReportKey, phraseFor } = useReportNarrative();
    return {
      calculateTrend,
      isAverageMetricType,
      signalForReportKey,
      phraseFor,
    };
  },
  data() {
    return {
      drilldownRequest: null,
      drilldownMetric: null,
      drilldownIndex: null,
    };
  },
  computed: {
    ...mapGetters({
      accountReport: 'getAccountReports',
      currentRole: 'getCurrentRole',
    }),
    accountSummary() {
      return this.$store.getters[this.accountSummaryKey] || {};
    },
    signals() {
      return this.accountSummary.signals || [];
    },
    isAdmin() {
      return this.currentRole === 'administrator';
    },
    canDrilldownPrev() {
      return this.findDrillableIndex(this.drilldownIndex - 1, -1) !== null;
    },
    canDrilldownNext() {
      return this.findDrillableIndex(this.drilldownIndex + 1, 1) !== null;
    },
    metrics() {
      const reportKeys = Object.keys(this.reportKeys);
      const infoText = {
        FIRST_RESPONSE_TIME: this.$t(
          `REPORT.METRICS.FIRST_RESPONSE_TIME.INFO_TEXT`
        ),
        FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT: this.$t(
          `REPORT.METRICS.FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT.INFO_TEXT`
        ),
        RESOLUTION_TIME: this.$t(`REPORT.METRICS.RESOLUTION_TIME.INFO_TEXT`),
      };
      return reportKeys.map(key => ({
        NAME: this.$t(`REPORT.METRICS.${key}.NAME`),
        KEY: this.reportKeys[key],
        DESC: this.$t(`REPORT.METRICS.${key}.DESC`),
        INFO_TEXT: infoText[key],
        TOOLTIP_TEXT: `REPORT.METRICS.${key}.TOOLTIP_TEXT`,
        trend: this.calculateTrend(this.reportKeys[key]),
        signal: this.signalForReportKey(this.signals, this.reportKeys[key]),
      }));
    },
  },
  methods: {
    getMetricMax(metric) {
      const data = this.accountReport.data[metric.KEY] || [];
      const values = data.map(element => element.value || 0);
      const counts = data.map(element => element.count || 0);
      const valueMax = values.length ? Math.max(...values) : 0;
      const countMax = counts.length ? Math.max(...counts) : 0;
      return { valueMax, countMax };
    },
    getCollection(metric) {
      if (!this.accountReport.data[metric.KEY]) {
        return {};
      }
      const data = this.accountReport.data[metric.KEY];
      const labels = data.map(element => {
        if (this.groupBy?.period === GROUP_BY_FILTER[2].period) {
          let week_date = new Date(fromUnixTime(element.timestamp));
          const first_day = week_date.getDate() - week_date.getDay();
          const last_day = first_day + 6;
          const week_first_date = new Date(week_date.setDate(first_day));
          const week_last_date = new Date(week_date.setDate(last_day));
          return `${format(week_first_date, 'dd-MMM')} - ${format(
            week_last_date,
            'dd-MMM'
          )}`;
        }
        if (this.groupBy?.period === GROUP_BY_FILTER[3].period) {
          return format(fromUnixTime(element.timestamp), 'MMM-yyyy');
        }
        if (this.groupBy?.period === GROUP_BY_FILTER[4].period) {
          return format(fromUnixTime(element.timestamp), 'yyyy');
        }
        return format(fromUnixTime(element.timestamp), 'dd-MMM');
      });
      const datasets = METRIC_CHART[metric.KEY].datasets.map(dataset => {
        switch (dataset.type) {
          case 'bar':
            return {
              ...dataset,
              yAxisID: 'y',
              label: metric.NAME,
              data: data.map(element => element.value),
            };
          case 'line':
            return {
              ...dataset,
              yAxisID: 'y1',
              label: this.$t('REPORT.METRICS.CONVERSATIONS.NAME'),
              data: data.map(element => element.count),
            };
          default:
            return dataset;
        }
      });
      return {
        labels,
        datasets,
      };
    },
    getChartOptions(metric) {
      const baseScales = METRIC_CHART[metric.KEY].scales;
      const options = {
        scales: {
          ...baseScales,
          y: {
            ...baseScales.y,
            ticks: { ...baseScales.y.ticks },
          },
          ...(baseScales.y1 && {
            y1: {
              ...baseScales.y1,
              ticks: { ...baseScales.y1.ticks },
            },
          }),
        },
      };

      const { valueMax, countMax } = this.getMetricMax(metric);
      if (options.scales?.y && valueMax > 0) {
        options.scales.y.suggestedMax = Math.ceil(valueMax * 1.1);
      }
      if (options.scales?.y1 && countMax > 0) {
        options.scales.y1.suggestedMax = Math.ceil(countMax * 1.1);
      }

      // Only add tooltip configuration for time-based metrics
      if (this.isAverageMetricType(metric.KEY)) {
        options.plugins = {
          tooltip: {
            callbacks: {
              label: ({ raw, dataIndex, dataset }) => {
                if (dataset?.type === 'line') {
                  return `${this.$t('REPORT.METRICS.CONVERSATIONS.NAME')}: ${raw}`;
                }
                return this.$t(metric.TOOLTIP_TEXT, {
                  metricValue: formatTime(raw || 0),
                  conversationCount:
                    this.accountReport.data[metric.KEY][dataIndex]?.count || 0,
                });
              },
            },
          },
        };
      }

      return options;
    },
    isDrilldownEnabled() {
      return !!(this.from && this.to);
    },
    onChartElementClick(metric, event) {
      if (!this.isDrilldownEnabled()) return;

      const dataPoint = this.accountReport.data[metric.KEY]?.[event.dataIndex];
      if (!this.canOpenDrilldown(metric, dataPoint)) return;
      if (!this.isAdmin) {
        useAlert(this.$t('REPORT.DRILLDOWN.ADMIN_ONLY'));
        return;
      }

      this.openDrilldownAt(metric, event.dataIndex);
    },
    openDrilldownAt(metric, dataIndex) {
      const dataPoint = this.accountReport.data[metric.KEY]?.[dataIndex];
      if (!this.canOpenDrilldown(metric, dataPoint)) return;

      const labels = this.getCollection(metric).labels || [];

      this.drilldownMetric = metric;
      this.drilldownIndex = dataIndex;
      this.drilldownRequest = {
        metric: metric.KEY,
        metricName: metric.NAME,
        bucketLabel: labels[dataIndex],
        bucketTimestamp: dataPoint.timestamp,
        bucketValue: dataPoint.value,
        isAverageMetric: this.isAverageMetricType(metric.KEY),
        from: this.from,
        to: this.to,
        type: this.reportType,
        id: this.selectedItemId,
        groupBy: this.groupBy?.period,
        businessHours: this.businessHours,
      };
    },
    navigateDrilldown(direction) {
      const nextIndex = this.findDrillableIndex(
        this.drilldownIndex + direction,
        direction
      );
      if (nextIndex === null) return;

      this.openDrilldownAt(this.drilldownMetric, nextIndex);
    },
    findDrillableIndex(startIndex, step) {
      if (!this.drilldownMetric) return null;

      const data = this.accountReport.data[this.drilldownMetric.KEY] || [];
      for (
        let index = startIndex;
        index >= 0 && index < data.length;
        index += step
      ) {
        if (this.canOpenDrilldown(this.drilldownMetric, data[index]))
          return index;
      }

      return null;
    },
    canOpenDrilldown(metric, dataPoint) {
      if (!dataPoint) return false;

      if (this.isAverageMetricType(metric.KEY)) {
        return dataPoint.count > 0;
      }

      return dataPoint.value > 0;
    },
    closeDrilldown() {
      this.drilldownRequest = null;
      this.drilldownMetric = null;
      this.drilldownIndex = null;
    },
  },
};
</script>

<template>
  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
    <div
      v-for="metric in metrics"
      :key="metric.KEY"
      class="flex flex-col gap-4 bg-n-solid-1 border border-n-weak rounded-xl p-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-2">
          <ChartStats
            :metric="metric"
            :signal="metric.signal"
            :account-summary-key="accountSummaryKey"
            :summary-fetching-key="summaryFetchingKey"
          />
          <span v-if="metric.DESC" class="text-sm text-n-slate-10">
            {{ metric.DESC }}
          </span>
        </div>
      </div>
      <div class="h-72 rounded-xl p-2">
        <woot-loading-state
          v-if="accountReport.isFetching[metric.KEY]"
          class="text-xs"
          :message="$t('REPORT.LOADING_CHART')"
        />
        <div v-else class="flex items-center justify-center h-full">
          <BarChart
            v-if="accountReport.data[metric.KEY]?.length"
            :collection="getCollection(metric)"
            :chart-options="getChartOptions(metric)"
            :clickable="isDrilldownEnabled()"
            @element-click="onChartElementClick(metric, $event)"
          />
          <span v-else class="text-sm text-n-slate-10">
            {{ $t('REPORT.NO_ENOUGH_DATA') }}
          </span>
        </div>
      </div>
      <p v-if="metric.signal" class="text-xs text-n-slate-11 -mt-2 px-1">
        {{ phraseFor(metric.signal) }}
      </p>
    </div>
  </div>
  <ReportDrilldownDrawer
    :id="drilldownRequest?.id"
    :open="!!drilldownRequest"
    :metric="drilldownRequest?.metric"
    :metric-name="drilldownRequest?.metricName"
    :bucket-label="drilldownRequest?.bucketLabel"
    :bucket-timestamp="drilldownRequest?.bucketTimestamp"
    :bucket-value="drilldownRequest?.bucketValue"
    :is-average-metric="drilldownRequest?.isAverageMetric"
    :from="drilldownRequest?.from"
    :to="drilldownRequest?.to"
    :type="drilldownRequest?.type"
    :group-by="drilldownRequest?.groupBy"
    :business-hours="drilldownRequest?.businessHours"
    :can-prev="canDrilldownPrev"
    :can-next="canDrilldownNext"
    @navigate="navigateDrilldown"
    @close="closeDrilldown"
  />
</template>
