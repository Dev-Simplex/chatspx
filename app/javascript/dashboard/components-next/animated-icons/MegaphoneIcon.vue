<script>
export default {
  name: 'MegaphoneIcon',
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
      <g
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
      >
        <path
          d="M11 6a13 13 0 0 0 8.4-2.8A1 1 0 0 1 21 4v12a1 1 0 0 1-1.6.8A13 13 0 0 0 11 14H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z"
        />
        <path
          d="M6 14a12 12 0 0 0 2.4 7.2a2 2 0 0 0 3.2-2.4A8 8 0 0 1 10 14M8 6v8"
        />
      </g>
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-megaphone 600ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-megaphone {
  0%,
  100% {
    transform: rotate(0deg) translateY(0);
  }
  10% {
    transform: rotate(-15deg) translateY(-1px);
  }
  20% {
    transform: rotate(15deg) translateY(0);
  }
  30% {
    transform: rotate(-10deg) translateY(-1px);
  }
  40% {
    transform: rotate(10deg);
  }
  50% {
    transform: rotate(0deg);
  }
}
</style>
