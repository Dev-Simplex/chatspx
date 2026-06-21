<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import ReportMetricCard from './ReportMetricCard.vue';
import ReportNarrativeSummary from './ReportNarrativeSummary.vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import ReportsAPI from 'dashboard/api/reports';

const props = defineProps({
  filters: {
    type: Object,
    required: true,
  },
});

const conversationCount = ref('0');
const messageCount = ref('0');
const resolutionRate = ref('0');
const handoffRate = ref('0');
const signals = ref([]);

const { signalByMetric } = useReportNarrative();
const resolutionSignal = computed(() =>
  signalByMetric(signals.value, 'bot_resolution_rate')
);
const handoffSignal = computed(() =>
  signalByMetric(signals.value, 'bot_handoff_rate')
);

const formatToPercent = value => {
  return value ? `${value}%` : '--';
};

const fetchMetrics = () => {
  if (!props.filters.to || !props.filters.from) {
    return;
  }
  ReportsAPI.getBotMetrics(props.filters).then(response => {
    conversationCount.value = response.data.conversation_count.toLocaleString();
    messageCount.value = response.data.message_count.toLocaleString();
    resolutionRate.value = response.data.resolution_rate.toString();
    handoffRate.value = response.data.handoff_rate.toString();
    signals.value = response.data.signals || [];
  });
};

watch(() => props.filters, fetchMetrics, { deep: true });

onMounted(fetchMetrics);
</script>

<template>
  <ReportNarrativeSummary :signals="signals" />
  <div
    class="flex flex-wrap mx-0 rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-5 shadow-sm"
  >
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.TOOLTIP')"
      :value="conversationCount"
      class="flex-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
      :value="messageCount"
      class="flex-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.TOOLTIP')"
      :value="formatToPercent(resolutionRate)"
      :signal="resolutionSignal"
      class="flex-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.TOOLTIP')"
      :value="formatToPercent(handoffRate)"
      :signal="handoffSignal"
      class="flex-1"
    />
  </div>
</template>
