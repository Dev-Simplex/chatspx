<script>
export default { name: 'ArrowRightIcon' };
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
      <path :class="{ 'anim-line': animating }" d="M5 12h14" />
      <path :class="{ 'anim-head': animating }" d="m12 5 7 7-7 7" />
    </svg>
  </div>
</template>

<style scoped>
.anim-line {
  transform-origin: left center;
  animation: arrow-r-line 400ms ease forwards;
}
.anim-head {
  animation: arrow-r-head 400ms ease forwards;
}
@keyframes arrow-r-line {
  0%,
  100% {
    transform: scaleX(1);
  }
  40% {
    transform: scaleX(0.6);
  }
}
@keyframes arrow-r-head {
  0%,
  100% {
    transform: translateX(0);
  }
  40% {
    transform: translateX(-3px);
  }
}
</style>
