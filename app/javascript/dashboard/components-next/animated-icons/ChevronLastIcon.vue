<script>
export default {
  name: 'ChevronLastIcon',
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
      class="overflow-visible"
      :class="[{ 'is-animating': animating }]"
    >
      <path
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="m7 18l6-6l-6-6m10 0v12"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-chevron-last 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-chevron-last {
  0% {
    transform: translateX(0);
    opacity: 1;
  }
  50% {
    transform: translateX(4px);
    opacity: 0.7;
  }
  100% {
    transform: translateX(0);
    opacity: 1;
  }
}
</style>
