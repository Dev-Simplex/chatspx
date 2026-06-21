<script>
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

export default {
  props: {
    label: {
      type: String,
      required: true,
    },
    value: {
      type: [String, Number],
      required: true,
    },
    toolTip: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      default: false,
    },
    signal: {
      type: Object,
      default: null,
    },
  },
  setup() {
    const { pillFor } = useReportNarrative();
    return { pillFor };
  },
  computed: {
    pill() {
      return this.pillFor(this.signal);
    },
  },
};
</script>

<template>
  <div
    class="flex flex-col gap-2 items-start justify-center min-w-[10rem] bg-n-solid-1 border border-n-weak rounded-xl p-5"
  >
    <span
      class="inline-flex items-center gap-1 text-xs font-medium uppercase tracking-wider text-n-slate-10"
    >
      {{ label }}
      <fluent-icon
        v-tooltip.right="toolTip"
        size="14"
        icon="information"
        type="outline"
        class="flex flex-shrink-0 text-n-slate-10"
      />
    </span>
    <div
      v-if="isLoading"
      class="w-12 h-6 mb-0.5 rounded-md bg-n-slate-3 animate-pulse"
    />

    <span
      v-else
      class="text-2xl font-semibold text-n-slate-12 tabular-nums mt-1"
    >
      {{ value }}
    </span>
    <span
      v-if="pill && !isLoading"
      class="text-xs inline-flex items-center gap-1 px-2 py-1 rounded-full border font-medium"
      :class="pill.colorClass"
    >
      <span>{{ pill.icon }}</span>
      <span>{{ pill.label }}</span>
    </span>
  </div>
</template>
