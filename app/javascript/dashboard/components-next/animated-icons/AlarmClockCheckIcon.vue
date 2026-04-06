<template>
  <div
    :class="props.class"
    :style="wrapStyle"
    @mouseenter="animating = true"
    @animationend="animating = false"
  >
    <svg
      xmlns="http://www.w3.org/2000/svg"
      :width="size"
      :height="size"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      :class="{ 'is-animating': animating }"
      style="overflow: visible;"
    >
      <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><circle cx="12" cy="13" r="8"/><path d="M5 3L2 6m20 0l-3-3M6.38 18.7L4 21m13.64-2.33L20 21M9 13l2 2l4-4"/></g>
    </svg>
  </div>
</template>

<script>
export default {
  name: 'AlarmClockCheckIcon',
};
</script>

<script setup>
import { ref, computed } from 'vue';

const props = defineProps({
  size: { type: Number, default: 16 },
  class: { type: String, default: '' },
});

const animating = ref(false);
const wrapStyle = computed(() => ({
  width: props.size + 'px',
  height: props.size + 'px',
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
}));
</script>

<style scoped>
svg.is-animating {
  animation: anim-alarm-clock-check 600ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-alarm-clock-check {
  0% { transform: rotate(0deg); }
  15% { transform: rotate(-15deg); }
  30% { transform: rotate(12deg); }
  45% { transform: rotate(-9deg); }
  60% { transform: rotate(6deg); }
  75% { transform: rotate(-3deg); }
  100% { transform: rotate(0deg); }
}
</style>