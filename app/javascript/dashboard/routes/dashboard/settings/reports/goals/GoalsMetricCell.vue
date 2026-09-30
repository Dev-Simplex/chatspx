<script setup>
// CHAT-177: um indicador de uma linha do ranking. Sem meta ou sem dado nunca vira 0%.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { goalTone, formatMetric, percentLabel } from './goalsFormat';

const props = defineProps({
  metric: { type: String, required: true },
  data: { type: Object, default: () => ({}) },
  // false para o colega de um atendente: o servidor já mandou actual/goal nulos.
  showNumbers: { type: Boolean, default: true },
});

const { t, locale } = useI18n();

const percent = computed(() => percentLabel(props.data?.attainment));
const tone = computed(() => goalTone(props.data?.attainment));

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
const barWidth = computed(() => {
  const value = Math.min((props.data?.attainment || 0) * 100, 100);
  return WIDTHS[Math.round(value / 5)];
});

const emptyLabel = computed(() => {
  if (!props.showNumbers) return t('PERFORMANCE_GOALS.HIDDEN');
  if (props.data?.goal == null) return t('PERFORMANCE_GOALS.NO_GOAL');
  return t('PERFORMANCE_GOALS.NO_DATA');
});

const numbers = computed(() => {
  const { actual, goal } = props.data || {};
  if (!props.showNumbers || actual == null) return '';
  const fmt = value => formatMetric(props.metric, value, locale.value);
  if (goal == null) return fmt(actual);
  return t('PERFORMANCE_GOALS.OF', { actual: fmt(actual), goal: fmt(goal) });
});
</script>

<template>
  <div class="min-w-[7.5rem]">
    <template v-if="percent">
      <span class="text-sm font-semibold tabular-nums" :class="tone.text">
        {{ percent }}
      </span>
      <div class="h-1 mt-1.5 overflow-hidden rounded-full bg-n-alpha-2">
        <div class="h-full rounded-full" :class="[tone.bar, barWidth]" />
      </div>
      <p v-if="numbers" class="mt-1 mb-0 text-xs tabular-nums text-n-slate-11">
        {{ numbers }}
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
