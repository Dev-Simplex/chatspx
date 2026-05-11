<script>
export default {
  name: 'ArrowDownToDotIcon',
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
        <path d="M12 2v14m7-7l-7 7l-7-7" />
        <circle cx="12" cy="21" r="1" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-arrow-down-to-dot 400ms cubic-bezier(0.34, 1.56, 0.64, 1)
    forwards;
}
@keyframes anim-arrow-down-to-dot {
  0% {
    transform: translateY(0);
  }
  40% {
    transform: translateY(3px);
  }
  60% {
    transform: translateY(1px);
  }
  100% {
    transform: translateY(0);
  }
}
</style>
