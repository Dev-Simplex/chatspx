<script>
export default { name: 'LockIcon' };
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
        :class="{ 'anim-shackle': animating }"
        d="M7 11V7a5 5 0 0 1 10 0v4"
      />
      <rect
        :class="{ 'anim-lock-body': animating }"
        width="18"
        height="11"
        x="3"
        y="11"
        rx="2"
        ry="2"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-shackle {
  transform-origin: 12px 11px;
  animation: lock-shackle 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-lock-body {
  transform-origin: 12px 16px;
  animation: lock-body 600ms cubic-bezier(0.4, 0, 0.2, 1) forwards;
}
@keyframes lock-shackle {
  0%,
  100% {
    transform: translateY(0);
  }
  30% {
    transform: translateY(-3px);
  }
  60% {
    transform: translateY(-1px);
  }
}
@keyframes lock-body {
  0% {
    transform: rotate(0deg) scale(1);
  }
  25% {
    transform: rotate(-3deg) scale(0.95);
  }
  50% {
    transform: rotate(1deg) scale(1.05);
  }
  75% {
    transform: rotate(-2deg) scale(0.98);
  }
  100% {
    transform: rotate(0deg) scale(1);
  }
}
</style>
