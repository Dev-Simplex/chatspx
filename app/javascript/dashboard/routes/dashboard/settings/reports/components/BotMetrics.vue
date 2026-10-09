<script setup>
import { formatPercent } from 'dashboard/helper/reportFormat';
import { ref, computed, watch, onMounted } from 'vue';
import { I18nT } from 'vue-i18n';
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
  return value ? formatPercent(value) : '--';
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
  <section
    v-if="Number(String(conversationCount).replace(/\D/g, '')) > 0"
    class="rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] p-5"
  >
    <h3
      class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
    >
      {{ $t('REPORT.PLAIN_SUMMARY.TITLE') }}
    </h3>
    <p class="mt-3 flex gap-3 text-base leading-relaxed text-n-slate-12">
      <span class="i-lucide-bot size-5 mt-1 shrink-0 text-n-brand" />
      <span class="min-w-0">
        <I18nT keypath="BOT_REPORTS.PLAIN_SUMMARY.TEXT" tag="span">
          <template #conversations>
            <strong>{{ conversationCount }}</strong>
          </template>
          <template #resolved>
            <strong>{{ formatToPercent(resolutionRate) }}</strong>
          </template>
          <template #handoff>
            <strong>{{ formatToPercent(handoffRate) }}</strong>
          </template>
          <template #messages>
            <strong>{{ messageCount }}</strong>
          </template>
        </I18nT>
      </span>
    </p>
    <p class="mt-4 text-sm text-n-slate-11">
      {{ $t('BOT_REPORTS.PLAIN_SUMMARY.HOW_TO_READ') }}
    </p>
  </section>
  <ReportNarrativeSummary :signals="signals" />
  <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
    <ReportMetricCard
      icon="i-lucide-messages-square"
      :label="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.TOOLTIP')"
      :value="conversationCount"
    />
    <ReportMetricCard
      icon="i-lucide-message-square-reply"
      :label="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
      :value="messageCount"
    />
    <ReportMetricCard
      icon="i-lucide-bot"
      :label="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.TOOLTIP')"
      :value="formatToPercent(resolutionRate)"
      :signal="resolutionSignal"
    />
    <ReportMetricCard
      icon="i-lucide-user-round-check"
      :label="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.TOOLTIP')"
      :value="formatToPercent(handoffRate)"
      :signal="handoffSignal"
    />
  </div>
</template>
