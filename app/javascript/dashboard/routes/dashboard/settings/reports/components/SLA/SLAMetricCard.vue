<script>
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

export default {
  props: {
    icon: { type: String, default: '' },
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
    class="flex flex-col gap-1 p-4 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0"
  >
    <span
      v-if="icon"
      class="flex items-center justify-center mb-2 rounded-lg size-9 bg-n-alpha-2 text-n-slate-11"
    >
      <span class="size-5" :class="icon" />
    </span>
    <span class="inline-flex items-center gap-1 text-sm text-n-slate-11">
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
      class="text-2xl sm:text-[30px] font-extrabold leading-none tracking-[-0.035em] text-n-slate-12 tabular-nums"
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
