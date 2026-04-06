<script>
export default { name: 'SearchIcon' };
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
      :class="{ 'is-animating': animating }"
      style="overflow: visible"
    >
      <circle cx="11" cy="11" r="8" />
      <path d="m21 21-4.34-4.34" />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-search 800ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-search {
  0% {
    transform: translate(0, 0);
  }
  33% {
    transform: translate(0, -4px);
  }
  66% {
    transform: translate(-3px, 0);
  }
  100% {
    transform: translate(0, 0);
  }
}
</style>
