<script setup>
import { computed } from 'vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
  icon: { type: String, default: '' },
  label: {
    type: String,
    required: true,
  },
  value: {
    type: String,
    required: true,
  },
  infoText: {
    type: String,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  signal: {
    type: Object,
    default: null,
  },
  // Tendência opcional: { text, tone } com tone em 'good' | 'bad' | 'flat'.
  trend: {
    type: Object,
    default: null,
  },
});

const { pillFor } = useReportNarrative();
const pill = computed(() => pillFor(props.signal));

const TREND_TONE_CLASS = {
  good: 'text-n-teal-11',
  bad: 'text-n-ruby-11',
  flat: 'text-n-slate-10',
};
const trendClass = computed(
  () => TREND_TONE_CLASS[props.trend?.tone] || TREND_TONE_CLASS.flat
);
</script>

<template>
  <div
    data-test-id="reportMetricContainer"
    class="flex flex-col gap-1 p-4 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0"
    :class="{
      'grayscale pointer-events-none opacity-30': disabled,
    }"
  >
    <span
      v-if="icon"
      class="flex items-center justify-center mb-2 rounded-lg size-9 bg-n-alpha-2 text-n-slate-11"
    >
      <span class="size-5" :class="icon" />
    </span>
    <h3 class="inline-flex items-center gap-1 text-sm text-n-slate-11">
      <span data-test-id="reportMetricLabel">{{ label }}</span>
      <fluent-icon
        v-tooltip="infoText"
        data-test-id="reportMetricInfo"
        size="14"
        icon="info"
        class="text-n-slate-11 my-0 mx-1 mt-0.5"
      />
    </h3>
    <h4
      data-test-id="reportMetricValue"
      class="m-0 text-2xl sm:text-[30px] font-extrabold leading-none tracking-[-0.035em] text-n-slate-12 tabular-nums"
    >
      {{ value }}
    </h4>
    <span
      v-if="trend"
      class="mt-1 block text-xs font-medium tabular-nums"
      :class="trendClass"
    >
      {{ trend.text }}
    </span>
    <span
      v-if="pill"
      class="text-xs inline-flex items-center gap-1 px-2 py-1 mt-2 rounded-full border font-medium"
      :class="pill.colorClass"
    >
      <span>{{ pill.icon }}</span>
      <span>{{ pill.label }}</span>
    </span>
  </div>
</template>
