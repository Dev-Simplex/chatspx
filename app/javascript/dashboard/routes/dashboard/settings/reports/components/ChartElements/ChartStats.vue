<script setup>
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { STATUS } from 'dashboard/store/constants';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  metric: {
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
});

const { t } = useI18n();

const { calculateTrend, displayMetric, isAverageMetricType, fetchingStatus } =
  useReportMetrics(props.accountSummaryKey, props.summaryFetchingKey);

const trendColor = (value, key) => {
  if (isAverageMetricType(key)) {
    return value > 0
      ? 'border-n-ruby-9 text-n-ruby-9'
      : 'border-n-teal-10 text-n-teal-10';
  }
  return value < 0
    ? 'border-n-ruby-9 text-n-ruby-9'
    : 'border-n-teal-10 text-n-teal-10';
};
</script>

<template>
  <div>
    <span class="text-xs font-medium uppercase tracking-wider text-n-slate-10">
      {{ metric.NAME }}
    </span>
    <div class="flex items-end gap-3 text-n-slate-12 mt-1">
      <div v-if="fetchingStatus === STATUS.FETCHING">
        <Spinner />
      </div>
      <div
        v-else-if="fetchingStatus === STATUS.FAILED"
        class="text-n-ruby-10 text-sm"
      >
        {{ t('REPORT.SUMMARY_FETCHING_FAILED') }}
      </div>
      <div
        v-else-if="fetchingStatus === STATUS.FINISHED"
        class="text-2xl font-semibold text-n-slate-12 tabular-nums"
      >
        {{ displayMetric(metric.KEY) }}
      </div>
      <div
        v-if="metric.trend && fetchingStatus === STATUS.FINISHED"
        class="text-xs flex items-center gap-1 px-2 py-1 rounded-full border"
        :class="trendColor(metric.trend, metric.KEY)"
      >
        <div
          v-if="metric.trend < 0"
          class="h-0 w-0 border-x-4 medium border-x-transparent border-t-[8px]"
          :class="trendColor(metric.trend, metric.KEY)"
        />
        <div
          v-else
          class="h-0 w-0 border-x-4 medium border-x-transparent border-b-[8px]"
          :class="trendColor(metric.trend, metric.KEY)"
        />
        <span class="font-medium"> {{ calculateTrend(metric.KEY) }}% </span>
      </div>
    </div>
  </div>
</template>
