<script setup>
import { computed } from 'vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
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
});

const { pillFor } = useReportNarrative();
const pill = computed(() => pillFor(props.signal));
</script>

<template>
  <div
    data-test-id="reportMetricContainer"
    class="bg-n-solid-1 border border-n-weak rounded-xl p-5"
    :class="{
      'grayscale pointer-events-none opacity-30': disabled,
    }"
  >
    <h3
      class="flex items-center m-0 text-xs font-medium uppercase tracking-wider text-n-slate-10"
    >
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
      class="mt-1 mb-0 text-2xl font-semibold text-n-slate-12 tabular-nums"
    >
      {{ value }}
    </h4>
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
