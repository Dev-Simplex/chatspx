<script>
export default {
  name: 'SlidersVerticalIcon',
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
        d="M10 8h4m-2 13v-9m0-4V3m5 13h4m-2-4V3m0 18v-5M3 14h4m-2-4V3m0 18v-7"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-sliders-vertical 400ms cubic-bezier(0.34, 1.56, 0.64, 1)
    forwards;
}
@keyframes anim-sliders-vertical {
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
