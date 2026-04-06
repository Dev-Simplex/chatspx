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
      <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M15 12h-5m5-4h-5m9 9V5a2 2 0 0 0-2-2H4"/><path d="M8 21h12a2 2 0 0 0 2-2v-1a1 1 0 0 0-1-1H11a1 1 0 0 0-1 1v1a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v2a1 1 0 0 0 1 1h3"/></g>
    </svg>
  </div>
</template>

<script>
export default {
  name: 'ScrollTextIcon',
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
  animation: anim-scroll-text 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-scroll-text {
  0%, 100% { transform: rotate(0deg) translateY(0); }
  25% { transform: rotate(-5deg) translateY(-1px); }
  50% { transform: rotate(3deg) translateY(0); }
  75% { transform: rotate(-2deg) translateY(-0.5px); }
}
</style>