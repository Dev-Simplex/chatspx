<script>
export default { name: 'SmileIcon' };
</script>

<script setup>
import { ref, computed } from 'vue';

const props = defineProps({
  size: { type: Number, default: 16 },
  class: { type: String, default: '' },
});

const animating = ref(false);
const pendingAnims = ref(0);

const onAnimEnd = () => {
  pendingAnims.value -= 1;
  if (pendingAnims.value <= 0) {
    animating.value = false;
    pendingAnims.value = 0;
  }
};

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
    @animationend="onAnimEnd"
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
      <circle :class="{ 'anim-face': animating }" cx="12" cy="12" r="10" />
      <path :class="{ 'anim-mouth': animating }" d="M8 14s1.5 2 4 2 4-2 4-2" />
      <g :class="{ 'anim-eyes': animating }">
        <path d="M9 9h.01" />
        <path d="M15 9h.01" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-face {
  transform-origin: 12px 12px;
  animation: smile-face 800ms ease-in-out forwards;
}
.anim-mouth {
  transform-origin: 12px 14px;
  animation: smile-mouth 500ms ease-in-out forwards 100ms;
}
.anim-eyes {
  transform-origin: 12px 9px;
  animation: smile-eyes 500ms ease-in-out forwards;
}
@keyframes smile-face {
  0%,
  100% {
    transform: scale(1) rotate(0deg);
  }
  25% {
    transform: scale(1.15) rotate(-3deg);
  }
  50% {
    transform: scale(1.05) rotate(3deg);
  }
  75% {
    transform: scale(1.1) rotate(0deg);
  }
}
@keyframes smile-mouth {
  0%,
  100% {
    transform: scaleY(1);
  }
  50% {
    transform: scaleY(1.3);
  }
}
@keyframes smile-eyes {
  0%,
  100% {
    transform: scale(1);
  }
  30% {
    transform: scale(1.5);
  }
  60% {
    transform: scale(0.8);
  }
  80% {
    transform: scale(1.2);
  }
}
</style>
