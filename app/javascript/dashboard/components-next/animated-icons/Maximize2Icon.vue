<script>
export default {
  name: 'Maximize2Icon',
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
        d="M15 3h6v6m0-6l-7 7M3 21l7-7m-1 7H3v-6"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-maximize-2 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-maximize-2 {
  0% {
    transform: scale(1) rotate(0deg);
  }
  30% {
    transform: scale(0.8) rotate(-90deg);
  }
  60% {
    transform: scale(1.15) rotate(0deg);
  }
  100% {
    transform: scale(1) rotate(0deg);
  }
}
</style>
