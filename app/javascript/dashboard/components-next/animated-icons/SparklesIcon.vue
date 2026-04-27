<script>
export default { name: 'SparklesIcon' };
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
    >
      <path
        :class="{ 'anim-sparkle': animating }"
        d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"
      />
      <g :class="{ 'anim-star-plus': animating }">
        <path d="M20 2v4" />
        <path d="M22 4h-4" />
      </g>
      <circle :class="{ 'anim-star-dot': animating }" cx="4" cy="20" r="2" />
    </svg>
  </div>
</template>

<style scoped>
.anim-sparkle {
  transform-origin: 12px 12px;
  animation: sparkle-main 700ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-star-plus {
  transform-origin: 20px 4px;
  animation: sparkle-plus 600ms ease forwards 100ms;
}
.anim-star-dot {
  transform-origin: 4px 20px;
  animation: sparkle-dot 800ms ease forwards 200ms;
}
@keyframes sparkle-main {
  0% {
    transform: translateY(0) scale(1);
    fill: transparent;
  }
  30% {
    transform: translateY(-1px) scale(1.1);
    fill: currentColor;
  }
  60% {
    transform: translateY(0) scale(0.95);
    fill: currentColor;
  }
  100% {
    transform: translateY(0) scale(1);
    fill: transparent;
  }
}
@keyframes sparkle-plus {
  0%,
  100% {
    transform: rotate(0deg) scale(1);
    opacity: 1;
  }
  50% {
    transform: rotate(90deg) scale(1.3);
    opacity: 0.6;
  }
}
@keyframes sparkle-dot {
  0%,
  40%,
  100% {
    opacity: 1;
    transform: scale(1);
  }
  20% {
    opacity: 0.3;
    transform: scale(0.6);
  }
  60% {
    opacity: 0.5;
    transform: scale(0.8);
  }
  80% {
    opacity: 1;
    transform: scale(1.2);
  }
}
</style>
