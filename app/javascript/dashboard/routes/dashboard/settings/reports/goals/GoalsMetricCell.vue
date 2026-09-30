<script setup>
// CHAT-177: um indicador de uma linha do ranking. Sem meta ou sem dado nunca vira 0%.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  metric: { type: String, required: true },
  data: { type: Object, default: () => ({}) },
  // false para o colega de um atendente: o servidor já mandou actual/goal nulos.
  showNumbers: { type: Boolean, default: true },
});

const { t, locale } = useI18n();

const attainment = computed(() => props.data?.attainment);
const percent = computed(() =>
  attainment.value == null ? null : Math.round(attainment.value * 100)
);
// Classes escritas por extenso: o Tailwind só gera o que aparece no código (sem estilo inline).
const WIDTHS = [
  'w-0', 'w-[5%]', 'w-[10%]', 'w-[15%]', 'w-[20%]', 'w-[25%]',
  'w-[30%]', 'w-[35%]', 'w-[40%]', 'w-[45%]', 'w-[50%]', 'w-[55%]',
  'w-[60%]', 'w-[65%]', 'w-[70%]', 'w-[75%]', 'w-[80%]', 'w-[85%]',
  'w-[90%]', 'w-[95%]', 'w-full',
];
const barWidth = computed(
  () => WIDTHS[Math.round(Math.min(percent.value || 0, 100) / 5)]
);

// Intl direto: o `n()` do vue-i18n com opções soltas quebra sem numberFormats configurado.
const format = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-'), {
    maximumFractionDigits: props.metric === 'first_response_time' ? 1 : 0,
  }).format(Number(value));

const emptyLabel = computed(() => {
  if (!props.showNumbers) return t('PERFORMANCE_GOALS.HIDDEN');
  if (props.data?.goal == null) return t('PERFORMANCE_GOALS.NO_GOAL');
  return t('PERFORMANCE_GOALS.NO_DATA');
});

// "4,2 min (meta 5 min)" no tempo de resposta; "92 / 80" nos demais.
const numbers = computed(() => {
  const { actual, goal } = props.data || {};
  if (!props.showNumbers || actual == null) return '';
  if (props.metric === 'first_response_time') {
    return goal == null
      ? t('PERFORMANCE_GOALS.MINUTES', { value: format(actual) })
      : t('PERFORMANCE_GOALS.MINUTES_WITH_GOAL', {
          value: format(actual),
          goal: format(goal),
        });
  }
  return goal == null
    ? format(actual)
    : t('PERFORMANCE_GOALS.OF_GOAL', {
        actual: format(actual),
        goal: format(goal),
      });
});

const barColor = computed(() => {
  if (percent.value >= 100) return 'bg-n-teal-9';
  if (percent.value >= 70) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
});
</script>

<template>
  <div class="min-w-[7rem]">
    <template v-if="percent != null">
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ `${percent}%` }}
        </span>
      </div>
      <div class="h-1.5 mt-1 rounded-full bg-n-alpha-2 overflow-hidden">
        <div class="h-full rounded-full" :class="[barColor, barWidth]" />
      </div>
      <p v-if="numbers" class="mt-1 mb-0 text-xs text-n-slate-11">
        {{ numbers }}
      </p>
    </template>
    <template v-else>
      <span class="text-sm text-n-slate-10">{{ emptyLabel }}</span>
      <p v-if="numbers" class="mt-1 mb-0 text-xs text-n-slate-11">
        {{ numbers }}
      </p>
    </template>
  </div>
</template>
