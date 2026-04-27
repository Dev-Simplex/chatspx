<script>
export default {
  name: 'CastleIcon',
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
        <path d="M10 5V3m4 2V3m1 18v-3a3 3 0 0 0-6 0v3m9-18v8m0-6H6m16 6H2" />
        <path d="M22 9v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9m4-6v8" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-castle 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-castle {
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
