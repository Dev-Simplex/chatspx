<script setup>
import LottieIcon from './LottieIcon.vue';

defineProps({
  animationData: { type: Object, default: null },
  fallbackIcon: { type: String, default: 'i-lucide-bar-chart-2' },
  value: { type: [Number, String], default: 0 },
  label: { type: String, default: '' },
  iconMode: { type: String, default: 'hover' },
});
</script>

<template>
  <div
    class="flex items-center gap-3 rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-sm dark:bg-n-solid-2"
  >
    <div
      class="flex size-10 items-center justify-center rounded-lg bg-primary-50 dark:bg-primary-900/20"
    >
      <LottieIcon
        v-if="animationData"
        :animation-data="animationData"
        :size="20"
        :mode="iconMode"
      />
      <i v-else class="size-5 text-primary-500" :class="[fallbackIcon]" />
    </div>
    <div>
      <p class="text-xl font-bold tabular-nums text-n-slate-12">{{ value }}</p>
      <p class="text-xs text-n-slate-10">{{ label }}</p>
    </div>
  </div>
</template>
