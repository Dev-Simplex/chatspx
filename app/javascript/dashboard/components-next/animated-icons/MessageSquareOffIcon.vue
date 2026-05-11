<script>
export default {
  name: 'MessageSquareOffIcon',
};
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
      class="overflow-visible"
      :class="[{ 'is-animating': animating }]"
    >
      <path
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M19 19H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.7.7 0 0 1 2 21.286V5a2 2 0 0 1 1.184-1.826M2 2l20 20M8.656 3H20a2 2 0 0 1 2 2v11.344"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-message-square-off 500ms cubic-bezier(0.34, 1.56, 0.64, 1)
    forwards;
}
@keyframes anim-message-square-off {
  0%,
  100% {
    transform: rotate(0deg) scale(1);
  }
  20% {
    transform: rotate(-8deg) scale(1.05);
  }
  40% {
    transform: rotate(6deg) scale(1.05);
  }
  60% {
    transform: rotate(-4deg) scale(1.02);
  }
  80% {
    transform: rotate(2deg) scale(1);
  }
}
</style>
