<script>
export default { name: 'StarIcon' };
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
      <path
        :class="{ 'anim-star': animating }"
        d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.12 2.12 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.12 2.12 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.12 2.12 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.12 2.12 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.12 2.12 0 0 0 1.597-1.16z"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-star {
  transform-origin: 12px 12px;
  animation: star-bounce 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes star-bounce {
  0% {
    transform: scale(1) rotate(0deg);
    fill: transparent;
  }
  30% {
    transform: scale(1.3) rotate(-15deg);
    fill: currentColor;
  }
  60% {
    transform: scale(0.9) rotate(5deg);
    fill: currentColor;
  }
  80% {
    transform: scale(1.05) rotate(-2deg);
    fill: transparent;
  }
  100% {
    transform: scale(1) rotate(0deg);
    fill: transparent;
  }
}
</style>
