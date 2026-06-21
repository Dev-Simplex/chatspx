<script setup>
import { computed } from 'vue';
import SLAMetricCard from './SLAMetricCard.vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
  hitRate: {
    type: String,
    required: true,
  },
  noOfBreaches: {
    type: Number,
    required: true,
  },
  noOfConversations: {
    type: Number,
    required: true,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  signals: {
    type: Array,
    default: () => [],
  },
});

const { signalByMetric } = useReportNarrative();
const hitRateSignal = computed(() =>
  signalByMetric(props.signals, 'sla_hit_rate')
);
</script>

<template>
  <div
    class="flex sm:flex-row flex-col w-full gap-4 sm:gap-12 rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-5 shadow-sm"
  >
    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.HIT_RATE.LABEL')"
      :value="hitRate"
      :tool-tip="$t('SLA_REPORTS.METRICS.HIT_RATE.TOOLTIP')"
      :is-loading="isLoading"
      :signal="hitRateSignal"
    />

    <div class="w-full sm:w-px bg-n-container/60" />
    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.LABEL')"
      :value="noOfBreaches"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.TOOLTIP')"
      :is-loading="isLoading"
    />
    <div class="w-full sm:w-px bg-n-container/60" />
    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.LABEL')"
      :value="noOfConversations"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.TOOLTIP')"
      :is-loading="isLoading"
    />
  </div>
</template>
