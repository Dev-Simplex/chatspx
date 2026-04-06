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
      <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"><path d="M12 6v6H8"/><circle cx="12" cy="12" r="10"/></g>
    </svg>
  </div>
</template>

<script>
export default {
  name: 'Clock9Icon',
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
  animation: anim-clock-9 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-clock-9 {
  0% { transform: scale(1); }
  20% { transform: scale(0.85); }
  40% { transform: scale(1.3); }
  60% { transform: scale(0.95); }
  80% { transform: scale(1.05); }
  100% { transform: scale(1); }
}
</style>