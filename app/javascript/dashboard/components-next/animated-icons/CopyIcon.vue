<script>
export default { name: 'CopyIcon' };
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
      <rect
        :class="{ 'anim-front': animating }"
        width="14"
        height="14"
        x="8"
        y="8"
        rx="2"
        ry="2"
      />
      <path
        :class="{ 'anim-back': animating }"
        d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-front {
  animation: copy-front 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-back {
  animation: copy-back 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes copy-front {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(-3px, -3px);
  }
}
@keyframes copy-back {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(3px, 3px);
  }
}
</style>
