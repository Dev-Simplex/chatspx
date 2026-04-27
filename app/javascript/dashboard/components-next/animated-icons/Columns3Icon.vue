<script>
export default {
  name: 'Columns3Icon',
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
      <g
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
      >
        <rect width="18" height="18" x="3" y="3" rx="2" />
        <path d="M9 3v18m6-18v18" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-columns-3 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-columns-3 {
  0%,
  100% {
    transform: translateY(0) rotate(0);
  }
  25% {
    transform: translateY(-2px) rotate(-3deg);
  }
  75% {
    transform: translateY(-1px) rotate(2deg);
  }
}
</style>
