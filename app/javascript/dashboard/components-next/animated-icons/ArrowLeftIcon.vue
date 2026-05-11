<script>
export default { name: 'ArrowLeftIcon' };
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
      <path :class="{ 'anim-head': animating }" d="m12 19-7-7 7-7" />
      <path :class="{ 'anim-line': animating }" d="M19 12H5" />
    </svg>
  </div>
</template>

<style scoped>
.anim-line {
  transform-origin: right center;
  animation: arrow-l-line 400ms ease forwards;
}
.anim-head {
  animation: arrow-l-head 400ms ease forwards;
}
@keyframes arrow-l-line {
  0%,
  100% {
    transform: scaleX(1);
  }
  40% {
    transform: scaleX(0.6);
  }
}
@keyframes arrow-l-head {
  0%,
  100% {
    transform: translateX(0);
  }
  40% {
    transform: translateX(3px);
  }
}
</style>
