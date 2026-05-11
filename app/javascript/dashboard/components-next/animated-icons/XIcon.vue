<script>
export default { name: 'XIcon' };
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
        :class="{ 'anim-line-1': animating }"
        pathLength="1"
        d="M18 6 6 18"
      />
      <path
        :class="{ 'anim-line-2': animating }"
        pathLength="1"
        d="m6 6 12 12"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-line-1 {
  stroke-dasharray: 1;
  animation: x-draw 300ms ease forwards;
}
.anim-line-2 {
  stroke-dasharray: 1;
  animation: x-draw 300ms ease forwards 150ms;
}
@keyframes x-draw {
  0% {
    stroke-dashoffset: 1;
    opacity: 0.3;
  }
  50% {
    opacity: 1;
  }
  100% {
    stroke-dashoffset: 0;
    opacity: 1;
  }
}
</style>
