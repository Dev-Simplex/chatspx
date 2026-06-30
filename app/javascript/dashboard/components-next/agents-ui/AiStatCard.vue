<script setup>
import { computed } from 'vue';
import NumberFlow from '@number-flow/vue';

const props = defineProps({
  value: { type: [Number, String], default: 0 },
  label: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-circle' },
  tint: { type: String, default: '#1faa59' },
  delta: { type: String, default: '' },
  deltaUp: { type: Boolean, default: true },
});
// Card de métrica iOS: ícone + valor com count-up (NumberFlow) + delta + sparkline (slot).
defineOptions({ name: 'AiStatCard' });
const isNum = computed(() => typeof props.value === 'number');
</script>

<template>
  <div
    class="p-4 rounded-2xl border shadow-sm transition-transform duration-200 ai-stat border-n-weak bg-n-solid-1/70 backdrop-blur-xl hover:-translate-y-0.5"
  >
    <div
      class="flex gap-2 items-center text-[12px] font-semibold text-n-slate-11"
    >
      <span
        class="grid place-items-center text-white rounded-lg size-6"
        :style="{ background: tint }"
      >
        <span :class="icon" class="size-3.5" />
      </span>
      {{ label }}
    </div>
    <div class="mt-2 text-[26px] font-extrabold tracking-tight text-n-slate-12">
      <NumberFlow v-if="isNum" :value="value" />
      <span v-else>{{ value }}</span>
    </div>
    <div
      v-if="delta"
      class="mt-0.5 text-[11.5px] font-semibold"
      :class="
        deltaUp ? 'text-g-600 dark:text-g-400' : 'text-r-600 dark:text-r-400'
      "
    >
      {{ delta }}
    </div>
    <slot name="spark" />
  </div>
</template>

<style scoped>
.ai-stat {
  animation: ai-rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) both;
}
@keyframes ai-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-stat {
    animation: none;
  }
}
</style>
