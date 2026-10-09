<script setup>
import { computed } from 'vue';
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { STATUS } from 'dashboard/store/constants';
import { useI18n } from 'vue-i18n';
import { formatChange } from 'dashboard/helper/reportFormat';

const props = defineProps({
  metric: {
    type: Object,
    default: () => ({}),
  },
  signal: {
    type: Object,
    default: null,
  },
  accountSummaryKey: {
    type: String,
    default: 'getAccountSummary',
  },
  summaryFetchingKey: {
    type: String,
    default: 'getAccountSummaryFetchingStatus',
  },
  // O numero abre a lista de conversas por tras dele (ReportDrilldownPanel).
  clickable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const { displayMetric, isAverageMetricType, fetchingStatus } = useReportMetrics(
  props.accountSummaryKey,
  props.summaryFetchingKey
);

const { pillFor, goalDisplay } = useReportNarrative();
const pill = computed(() => pillFor(props.signal));

// A variacao em frase ("5% a menos que no periodo anterior") e, quando da para julgar, se isso e bom:
// tempo que cai e bom, resolucao que sobe e boa; volume de conversa e mensagem nao tem certo ou errado.
const HIGHER_IS_BETTER = ['resolutions_count'];

const trendVerdict = (value, key) => {
  if (isAverageMetricType(key)) return value < 0 ? 'good' : 'bad';
  if (HIGHER_IS_BETTER.includes(key)) return value > 0 ? 'good' : 'bad';
  return 'neutral';
};

const TREND_CLASSES = {
  good: 'bg-n-teal-3 text-n-teal-11',
  bad: 'bg-n-ruby-3 text-n-ruby-11',
  neutral: 'bg-n-alpha-2 text-n-slate-11',
};

const trend = computed(() => {
  if (!props.metric.trend) return null;
  const change = formatChange(props.metric.trend, t);
  const verdict = trendVerdict(props.metric.trend, props.metric.KEY);
  return {
    arrow: change.direction === 'down' ? '▼' : '▲',
    text: t('REPORT.CHANGE.VS_PREVIOUS', { change: change.text }),
    verdict:
      verdict === 'neutral'
        ? ''
        : t(`REPORT.CHANGE.VERDICT.${verdict.toUpperCase()}`),
    classes: TREND_CLASSES[verdict],
  };
});
</script>

<template>
  <div>
    <span class="text-sm font-medium text-n-slate-11">
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
      <button
        v-else-if="fetchingStatus === STATUS.FINISHED && clickable"
        type="button"
        class="p-0 m-0 text-left text-3xl font-semibold tracking-tight text-n-slate-12 tabular-nums underline decoration-dotted decoration-n-slate-8 underline-offset-4 hover:text-n-brand hover:decoration-n-brand"
        :title="t('REPORT.DRILLDOWN.OPEN')"
        @click="emit('select')"
      >
        {{ displayMetric(metric.KEY) }}
      </button>
      <div
        v-else-if="fetchingStatus === STATUS.FINISHED"
        class="text-3xl font-semibold tracking-tight text-n-slate-12 tabular-nums"
      >
        {{ displayMetric(metric.KEY) }}
      </div>
    </div>
    <div
      v-if="trend && fetchingStatus === STATUS.FINISHED"
      class="mt-2 inline-flex flex-wrap items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold"
      :class="trend.classes"
    >
      <span aria-hidden="true">{{ trend.arrow }}</span>
      <span>{{ trend.text }}</span>
      <span v-if="trend.verdict" class="font-semibold">
        {{ trend.verdict }}
      </span>
    </div>
    <div class="flex items-end gap-3 mt-1">
      <div
        v-if="pill && fetchingStatus === STATUS.FINISHED"
        class="text-xs flex items-center gap-1 px-2 py-1 rounded-full border font-medium"
        :class="pill.colorClass"
      >
        <span>{{ pill.icon }}</span>
        <span>
          {{
            t('REPORT.NARRATIVE.VS_GOAL_PILL', {
              level: pill.label,
              goal: goalDisplay(signal),
            })
          }}
        </span>
      </div>
    </div>
  </div>
</template>
