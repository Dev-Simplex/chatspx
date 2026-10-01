<script setup>
// CHAT-177: um indicador de uma linha do ranking. Sem meta ou sem dado nunca vira 0%.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  metricTone,
  formatMetric,
  percentLabel,
  pace,
  gap,
} from './goalsFormat';

const props = defineProps({
  metric: { type: String, required: true },
  data: { type: Object, default: () => ({}) },
  // false para o colega de um atendente: o servidor já mandou actual/goal nulos.
  showNumbers: { type: Boolean, default: true },
  // monthProgress do mês corrente; null em mês fechado.
  progress: { type: Object, default: null },
});

const { t, locale } = useI18n();

const percent = computed(() => percentLabel(props.data?.attainment));
const tone = computed(() =>
  metricTone(props.metric, props.data, props.progress)
);
const fmt = value => formatMetric(props.metric, value, locale.value);

// Classes por extenso: o Tailwind só gera o que aparece no código (sem estilo inline).
const WIDTHS = [
  'w-0',
  'w-[5%]',
  'w-[10%]',
  'w-[15%]',
  'w-[20%]',
  'w-[25%]',
  'w-[30%]',
  'w-[35%]',
  'w-[40%]',
  'w-[45%]',
  'w-[50%]',
  'w-[55%]',
  'w-[60%]',
  'w-[65%]',
  'w-[70%]',
  'w-[75%]',
  'w-[80%]',
  'w-[85%]',
  'w-[90%]',
  'w-[95%]',
  'w-full',
];
const widthOf = fraction =>
  WIDTHS[Math.round(Math.min(fraction || 0, 1) * 20)];
const barWidth = computed(() => widthOf(props.data?.attainment));
const rhythm = computed(() => pace(props.metric, props.data, props.progress));
// Faixa clara: onde o indicador devia estar hoje (fração do mês já vivida).
const paceWidth = computed(() =>
  rhythm.value ? widthOf(props.progress.fraction) : null
);

const emptyLabel = computed(() => {
  if (!props.showNumbers) return t('PERFORMANCE_GOALS.HIDDEN');
  if (props.data?.goal == null) return t('PERFORMANCE_GOALS.NO_GOAL');
  return t('PERFORMANCE_GOALS.NO_DATA');
});

const numbers = computed(() => {
  const { actual, goal } = props.data || {};
  if (!props.showNumbers || actual == null) return '';
  if (goal == null) return fmt(actual);
  return t('PERFORMANCE_GOALS.OF', { actual: fmt(actual), goal: fmt(goal) });
});

// Mapa explícito: chave dinâmica de i18n some do bundle no build.
const GAP_KEYS = {
  resolved_conversations: 'PERFORMANCE_GOALS.GAP.RESOLVED_CONVERSATIONS',
  kanban_wins: 'PERFORMANCE_GOALS.GAP.KANBAN_WINS',
  nps: 'PERFORMANCE_GOALS.GAP.NPS',
  first_response_time: 'PERFORMANCE_GOALS.GAP.FIRST_RESPONSE_TIME',
};
const gapLabel = computed(() => {
  const distance = gap(props.metric, props.data);
  if (!props.showNumbers || !distance) return '';
  if (distance < 0) {
    return t('PERFORMANCE_GOALS.ABOVE', { value: fmt(-distance) });
  }
  return t(GAP_KEYS[props.metric], { value: fmt(distance) }, distance);
});
</script>

<template>
  <div class="min-w-[7.5rem]">
    <template v-if="percent">
      <span
        class="inline-flex items-center gap-1 text-sm font-semibold tabular-nums"
        :class="tone.text"
      >
        <span
          v-if="data.attainment >= 1"
          class="i-lucide-circle-check-big size-3.5"
        />
        {{ percent }}
      </span>
      <div
        class="relative h-1.5 mt-1.5 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          v-if="paceWidth"
          class="absolute inset-y-0 rounded-full ltr:left-0 rtl:right-0 bg-n-slate-6"
          :class="paceWidth"
        />
        <div class="relative h-full rounded-full" :class="[tone.bar, barWidth]" />
      </div>
      <p v-if="numbers" class="mt-1 mb-0 text-xs tabular-nums text-n-slate-11">
        {{ numbers }}
      </p>
      <p v-if="gapLabel" class="mb-0 text-xs tabular-nums" :class="tone.text">
        {{ gapLabel }}
      </p>
      <p
        v-if="rhythm?.expected && showNumbers && data.attainment < 1"
        class="mb-0 text-xs tabular-nums text-n-slate-10"
      >
        {{
          $t('PERFORMANCE_GOALS.EXPECTED', { value: fmt(rhythm.expected) })
        }}
      </p>
    </template>
    <template v-else>
      <span class="text-xs text-n-slate-10">{{ emptyLabel }}</span>
      <p v-if="numbers" class="mt-1 mb-0 text-xs tabular-nums text-n-slate-11">
        {{ numbers }}
      </p>
    </template>
  </div>
</template>
