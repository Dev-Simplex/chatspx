<script>
import { mapGetters } from 'vuex';
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import { GROUP_BY_FILTER, METRIC_CHART } from './constants';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { formatDuration } from 'dashboard/helper/reportFormat';
import ChartStats from './components/ChartElements/ChartStats.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import ReportDrilldownPanel from 'dashboard/components-next/reports/ReportDrilldownPanel.vue';

export default {
  components: { ChartStats, BarChart, ReportDrilldownPanel },
  props: {
    groupBy: {
      type: Object,
      default: () => ({}),
    },
    accountSummaryKey: {
      type: String,
      default: 'getAccountSummary',
    },
    summaryFetchingKey: {
      type: String,
      default: 'getAccountSummaryFetchingStatus',
    },
    // Filtros da tela ({ from, to, type, id, businessHours, inboxId }): com eles, cada numero abre
    // a lista de conversas por tras dele.
    drilldownFilters: {
      type: Object,
      default: null,
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
    return { drilldownMetric: null };
  },
  computed: {
    ...mapGetters({
      accountReport: 'getAccountReports',
    }),
    accountSummary() {
      return this.$store.getters[this.accountSummaryKey] || {};
    },
    signals() {
      return this.accountSummary.signals || [];
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
    // "Como ler" + o ponto mais alto e o mais baixo do grafico, em frase.
    chartCaption(metric) {
      const data = (this.accountReport.data[metric.KEY] || []).filter(
        point => point.value !== null && point.value !== undefined
      );
      if (data.length < 2) return '';
      const labels = this.getCollection(metric).labels || [];
      const all = this.accountReport.data[metric.KEY];
      const isTime = this.isAverageMetricType(metric.KEY);
      const show = value =>
        isTime
          ? formatDuration(value, this.$t)
          : Number(value).toLocaleString();
      const ranked = (isTime ? data.filter(point => point.value > 0) : data)
        .slice()
        .sort((a, b) => b.value - a.value);
      if (ranked.length < 2) return '';
      const high = ranked[0];
      const low = ranked[ranked.length - 1];
      const period = this.groupBy?.period || 'day';
      const how = this.$t(
        `REPORT.CHART_CAPTION.${isTime ? 'HOW_TIME' : 'HOW_COUNT'}.${period.toUpperCase()}`
      );
      const peak = this.$t(
        `REPORT.CHART_CAPTION.${isTime ? 'PEAK_TIME' : 'PEAK_COUNT'}`,
        {
          high: labels[all.indexOf(high)],
          highValue: show(high.value),
          low: labels[all.indexOf(low)],
          lowValue: show(low.value),
        }
      );
      return `${how} ${peak}`;
    },
    openDrilldown(metric) {
      this.drilldownMetric = { key: metric.KEY, name: metric.NAME };
    },
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
          return `${format(week_first_date, 'dd/MM')} - ${format(
            week_last_date,
            'dd/MM'
          )}`;
        }
        if (this.groupBy?.period === GROUP_BY_FILTER[3].period) {
          return format(fromUnixTime(element.timestamp), 'MM/yyyy');
        }
        if (this.groupBy?.period === GROUP_BY_FILTER[4].period) {
          return format(fromUnixTime(element.timestamp), 'yyyy');
        }
        return format(fromUnixTime(element.timestamp), 'dd/MM');
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

      if (this.isAverageMetricType(metric.KEY) && options.scales?.y) {
        const tickCallback = options.scales.y.ticks.callback;
        options.scales.y.ticks.callback = (value, index, ticks) =>
          tickCallback(value, index, ticks) === ''
            ? ''
            : formatDuration(value, this.$t);
      }

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
                  metricValue: formatDuration(raw || 0, this.$t),
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
            :clickable="!!drilldownFilters"
            @select="openDrilldown(metric)"
          />
          <span v-if="metric.DESC" class="text-sm text-n-slate-10">
            {{ metric.DESC }}
          </span>
          <button
            v-if="drilldownFilters"
            type="button"
            class="flex items-center gap-1 text-sm font-medium text-n-brand hover:underline w-fit"
            @click="openDrilldown(metric)"
          >
            <span class="i-lucide-list size-4" />
            {{ $t('REPORT.DRILLDOWN.OPEN') }}
          </button>
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
          />
          <span v-else class="text-sm text-n-slate-10">
            {{ $t('REPORT.NO_ENOUGH_DATA') }}
          </span>
        </div>
      </div>
      <p
        v-if="chartCaption(metric)"
        class="text-sm text-n-slate-11 -mt-2 px-1 leading-relaxed"
      >
        {{ chartCaption(metric) }}
      </p>
      <p v-if="metric.signal" class="text-xs text-n-slate-11 -mt-2 px-1">
        {{ phraseFor(metric.signal) }}
      </p>
    </div>
    <ReportDrilldownPanel
      v-if="drilldownMetric && drilldownFilters"
      :metric="drilldownMetric"
      :filters="drilldownFilters"
      @close="drilldownMetric = null"
    />
  </div>
</template>
