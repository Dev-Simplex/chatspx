<script setup>
defineProps({
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
});
</script>

<template>
  <div
    data-test-id="reportMetricContainer"
    class="bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl p-5"
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
  </div>
</template>
