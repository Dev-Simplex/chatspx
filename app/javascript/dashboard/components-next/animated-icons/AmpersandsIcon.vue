<script>
export default {
  name: 'AmpersandsIcon',
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
        d="M10 17c-5-3-7-7-7-9a2 2 0 0 1 4 0c0 2.5-5 2.5-5 6c0 1.7 1.3 3 3 3c2.8 0 5-2.2 5-5m12 5c-5-3-7-7-7-9a2 2 0 0 1 4 0c0 2.5-5 2.5-5 6c0 1.7 1.3 3 3 3c2.8 0 5-2.2 5-5"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-ampersands 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-ampersands {
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
