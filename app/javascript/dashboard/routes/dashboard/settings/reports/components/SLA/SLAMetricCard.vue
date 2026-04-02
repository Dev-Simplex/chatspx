<script>
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
  },
};
</script>

<template>
  <div
    class="flex flex-col gap-2 items-start justify-center min-w-[10rem] bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl p-5"
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

    <span v-else class="text-2xl font-semibold text-n-slate-12 tabular-nums mt-1">
      {{ value }}
    </span>
  </div>
</template>
