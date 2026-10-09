<script setup>
import { computed } from 'vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
  icon: { type: String, default: '' },
  label: {
    type: String,
    required: true,
  },
  tooltip: {
    type: String,
    required: true,
  },
  value: {
    type: [String, Number],
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
});

const { pillFor } = useReportNarrative();
const pill = computed(() => pillFor(props.signal));
</script>

<template>
  <div
    class="flex flex-col gap-1 p-4 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0"
  >
    <span
      v-if="icon"
      class="flex items-center justify-center mb-2 rounded-lg size-9 bg-n-alpha-2 text-n-slate-11"
    >
      <span class="size-5" :class="icon" />
    </span>
    <span class="inline-flex items-center gap-1 text-sm text-n-slate-11">
      {{ label }}
      <span
        v-tooltip.right="tooltip"
        class="i-lucide-info flex flex-shrink-0 text-n-slate-10 size-3.5"
      />
    </span>
    <div
      v-if="isLoading"
      class="w-16 h-8 rounded-md bg-n-slate-3 animate-pulse"
    />
    <span
      v-else
      class="text-[30px] font-extrabold leading-none tracking-[-0.035em] text-n-slate-12 tabular-nums"
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
