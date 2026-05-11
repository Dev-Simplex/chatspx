<script>
export default { name: 'UserIcon' };
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
      <circle
        :class="{ 'anim-head': animating }"
        pathLength="1"
        cx="12"
        cy="7"
        r="4"
      />
      <path
        :class="{ 'anim-body': animating }"
        pathLength="1"
        d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-head {
  stroke-dasharray: 1;
  transform-origin: 12px 7px;
  animation: user-head 400ms ease forwards;
}
.anim-body {
  stroke-dasharray: 1;
  animation: user-body 400ms ease forwards 200ms;
}
@keyframes user-head {
  0% {
    stroke-dashoffset: 1;
    transform: scale(0.5);
  }
  100% {
    stroke-dashoffset: 0;
    transform: scale(1);
  }
}
@keyframes user-body {
  0% {
    stroke-dashoffset: 1;
    opacity: 0;
  }
  30% {
    opacity: 1;
  }
  100% {
    stroke-dashoffset: 0;
    opacity: 1;
  }
}
</style>
