<script>
export default { name: 'EyeIcon' };
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
      <path
        :class="{ 'anim-eyelid': animating }"
        d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"
      />
      <circle :class="{ 'anim-pupil': animating }" cx="12" cy="12" r="3" />
    </svg>
  </div>
</template>

<style scoped>
.anim-eyelid {
  transform-origin: 12px 12px;
  animation: eye-blink 400ms ease-in-out forwards;
}
.anim-pupil {
  transform-origin: 12px 12px;
  animation: pupil-shrink 400ms ease-in-out forwards;
}
@keyframes eye-blink {
  0%,
  100% {
    transform: scaleY(1);
    opacity: 1;
  }
  40% {
    transform: scaleY(0.1);
    opacity: 0.3;
  }
  70% {
    transform: scaleY(1);
    opacity: 1;
  }
}
@keyframes pupil-shrink {
  0%,
  100% {
    transform: scale(1);
    opacity: 1;
  }
  40% {
    transform: scale(0.3);
    opacity: 0.3;
  }
  70% {
    transform: scale(1);
    opacity: 1;
  }
}
</style>
