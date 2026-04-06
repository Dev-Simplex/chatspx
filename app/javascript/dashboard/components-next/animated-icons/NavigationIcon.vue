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
      <path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m3 11l19-9l-9 19l-2-8z"/>
    </svg>
  </div>
</template>

<script>
export default {
  name: 'NavigationIcon',
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
  animation: anim-navigation 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-navigation {
  0%, 100% { transform: rotate(0deg) scale(1); }
  20% { transform: rotate(-8deg) scale(1.05); }
  40% { transform: rotate(6deg) scale(1.05); }
  60% { transform: rotate(-4deg) scale(1.02); }
  80% { transform: rotate(2deg) scale(1); }
}
</style>