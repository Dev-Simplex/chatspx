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
      <path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6.87 6.87a8 8 0 1 0 11.26 11.26m1.77-3.88a8 8 0 0 0-9.15-9.15M22 6l-3-3M6.26 18.67L4 21M2 2l20 20M4 4L2 6"/>
    </svg>
  </div>
</template>

<script>
export default {
  name: 'AlarmClockOffIcon',
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
  animation: anim-alarm-clock-off 600ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-alarm-clock-off {
  0% { transform: rotate(0deg); }
  15% { transform: rotate(-15deg); }
  30% { transform: rotate(12deg); }
  45% { transform: rotate(-9deg); }
  60% { transform: rotate(6deg); }
  75% { transform: rotate(-3deg); }
  100% { transform: rotate(0deg); }
}
</style>