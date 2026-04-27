<script>
export default { name: 'CheckIcon' };
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
    >
      <path
        :class="{ 'anim-check': animating }"
        pathLength="1"
        d="M20 6L9 17l-5-5"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-check {
  stroke-dasharray: 1;
  animation: draw-check 400ms ease forwards;
}
@keyframes draw-check {
  0% {
    stroke-dashoffset: 1;
    opacity: 0.5;
  }
  30% {
    opacity: 1;
  }
  100% {
    stroke-dashoffset: 0;
    opacity: 1;
  }
}
</style>
