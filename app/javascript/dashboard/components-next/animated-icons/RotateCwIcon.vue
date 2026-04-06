<script>
export default { name: 'RotateCwIcon' };
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
      style="overflow: visible"
    >
      <g :class="{ 'anim-rotate': animating }">
        <path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8" />
        <path d="M21 3v5h-5" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-rotate {
  transform-origin: 12px 12px;
  animation: rotate-cw-spin 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes rotate-cw-spin {
  0% {
    transform: rotate(0deg);
  }
  60% {
    transform: rotate(65deg);
  }
  100% {
    transform: rotate(50deg);
  }
}
</style>
