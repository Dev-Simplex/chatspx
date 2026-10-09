<script setup>
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';
import SLAMetricCard from './SLAMetricCard.vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import { formatPercent } from 'dashboard/helper/reportFormat';

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
// A API manda "76.47%"; aqui vira "76,5%".
const hitRateLabel = computed(() => {
  const value = parseFloat(props.hitRate);
  return Number.isNaN(value) ? props.hitRate : formatPercent(value);
});
const hitRateSignal = computed(() =>
  signalByMetric(props.signals, 'sla_hit_rate')
);
</script>

<template>
  <section
    v-if="!isLoading && noOfConversations > 0"
    class="rounded-xl border border-n-weak bg-n-solid-2 p-5"
  >
    <h3 class="text-base font-semibold text-n-slate-12">
      {{ $t('REPORT.PLAIN_SUMMARY.TITLE') }}
    </h3>
    <p class="mt-3 flex gap-3 text-base leading-relaxed text-n-slate-12">
      <span class="i-lucide-alarm-clock size-5 mt-1 shrink-0 text-n-brand" />
      <span class="min-w-0">
        <I18nT keypath="SLA_REPORTS.PLAIN_SUMMARY.TEXT" tag="span">
          <template #conversations>
            <strong>{{ noOfConversations.toLocaleString() }}</strong>
          </template>
          <template #rate>
            <strong>{{ hitRateLabel }}</strong>
          </template>
          <template #misses>
            <strong>{{ noOfBreaches.toLocaleString() }}</strong>
          </template>
        </I18nT>
      </span>
    </p>
    <p class="mt-4 text-sm text-n-slate-11">
      {{ $t('SLA_REPORTS.PLAIN_SUMMARY.HOW_TO_READ') }}
    </p>
  </section>
  <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
    <SLAMetricCard
      icon="i-lucide-alarm-clock-check"
      :label="$t('SLA_REPORTS.METRICS.HIT_RATE.LABEL')"
      :value="hitRateLabel"
      :tool-tip="$t('SLA_REPORTS.METRICS.HIT_RATE.TOOLTIP')"
      :is-loading="isLoading"
      :signal="hitRateSignal"
    />
    <SLAMetricCard
      icon="i-lucide-alarm-clock-off"
      :label="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.LABEL')"
      :value="noOfBreaches"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.TOOLTIP')"
      :is-loading="isLoading"
    />
    <SLAMetricCard
      icon="i-lucide-messages-square"
      :label="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.LABEL')"
      :value="noOfConversations"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.TOOLTIP')"
      :is-loading="isLoading"
    />
  </div>
</template>
