<script setup>
import { computed } from 'vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

const props = defineProps({
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
    class="flex flex-col gap-2 items-start justify-center min-w-[10rem] bg-n-solid-1 border border-n-weak rounded-xl p-5"
  >
    <span
      class="inline-flex items-center gap-1 text-xs font-medium uppercase tracking-wider text-n-slate-10"
    >
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
