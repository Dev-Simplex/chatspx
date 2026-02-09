<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { formatTime } from '@chatwoot/utils';
import { STATUS } from 'dashboard/store/constants';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useI18n } from 'vue-i18n';
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  accountSummaryKey: {
    type: String,
    default: 'getAccountSummary',
  },
  summaryFetchingKey: {
    type: String,
    default: 'getAccountSummaryFetchingStatus',
  },
  showTransferMetrics: {
    type: Boolean,
    default: true,
  },
});

const { t } = useI18n();
const summary = useMapGetter(props.accountSummaryKey);
const { fetchingStatus, isAverageMetricType } = useReportMetrics(
  props.accountSummaryKey,
  props.summaryFetchingKey
);

const formatMetric = key => {
  const value = summary.value?.[key];
  if (!value) return '--';
  if (isAverageMetricType(key)) return formatTime(value);
  return Number(value || 0).toLocaleString();
};

const formatCount = key => {
  const value = summary.value?.[key];
  if (!value) return '--';
  return Number(value).toLocaleString();
};

const insightCards = computed(() => {
  const baseCards = [
    {
      id: 'avg_first_response_time',
      label: t('REPORT.INSIGHTS.AVG_FIRST_RESPONSE_TIME'),
      valueKey: 'avg_first_response_time',
      countKey: 'first_response_count',
    },
    {
      id: 'p50_first_response_time',
      label: t('REPORT.INSIGHTS.P50_FIRST_RESPONSE_TIME'),
      valueKey: 'p50_first_response_time',
      countKey: 'first_response_count',
    },
    {
      id: 'p90_first_response_time',
      label: t('REPORT.INSIGHTS.P90_FIRST_RESPONSE_TIME'),
      valueKey: 'p90_first_response_time',
      countKey: 'first_response_count',
    },
    {
      id: 'avg_reply_time',
      label: t('REPORT.INSIGHTS.AVG_REPLY_TIME'),
      valueKey: 'reply_time',
      countKey: null,
    },
  ];

  if (!props.showTransferMetrics) {
    return baseCards;
  }

  return [
    ...baseCards,
    {
      id: 'avg_first_response_time_after_assignment',
      label: t('REPORT.INSIGHTS.AVG_FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT'),
      valueKey: 'avg_first_response_time_after_assignment',
      countKey: 'first_response_after_assignment_count',
    },
    {
      id: 'p50_first_response_time_after_assignment',
      label: t('REPORT.INSIGHTS.P50_FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT'),
      valueKey: 'p50_first_response_time_after_assignment',
      countKey: 'first_response_after_assignment_count',
    },
    {
      id: 'p90_first_response_time_after_assignment',
      label: t('REPORT.INSIGHTS.P90_FIRST_RESPONSE_TIME_AFTER_ASSIGNMENT'),
      valueKey: 'p90_first_response_time_after_assignment',
      countKey: 'first_response_after_assignment_count',
    },
  ];
});
</script>

<template>
  <section
    class="rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-6 shadow-sm"
  >
    <div class="flex items-center justify-between gap-3">
      <div class="flex flex-col gap-2">
        <span class="text-xs uppercase tracking-[0.2em] text-n-slate-10">
          {{ t('REPORT.INSIGHTS.EYEBROW') }}
        </span>
        <h3 class="text-xl font-semibold text-n-slate-12">
          {{ title || t('REPORT.INSIGHTS.TITLE') }}
        </h3>
      </div>
      <div v-if="fetchingStatus === STATUS.FETCHING" class="text-n-slate-11">
        <Spinner />
      </div>
    </div>
    <div
      class="mt-5 grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
    >
      <div
        v-for="card in insightCards"
        :key="card.id"
        class="rounded-2xl border border-n-container/40 bg-n-background/80 p-4 shadow-sm"
      >
        <div class="flex items-center justify-between">
          <p class="text-[11px] uppercase tracking-[0.2em] text-n-slate-10">
            {{ card.label }}
          </p>
          <span class="h-2 w-2 rounded-full bg-n-brand/70" />
        </div>
        <div class="mt-2 text-2xl font-semibold text-n-slate-12">
          {{ formatMetric(card.valueKey) }}
        </div>
        <p v-if="card.countKey" class="mt-1 text-xs text-n-slate-10">
          {{ t('REPORT.INSIGHTS.BASE') }} {{ formatCount(card.countKey) }}
        </p>
      </div>
    </div>
  </section>
</template>
