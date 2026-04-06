<script>
export default { name: 'MessageCircleIcon' };
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
      style="overflow: visible"
    >
      <path
        :class="{ 'anim-bubble': animating }"
        d="M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092a10 10 0 1 0-4.777-4.719"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-bubble {
  transform-origin: 12px 12px;
  animation: msg-wobble 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes msg-wobble {
  0% {
    transform: scale(1) rotate(0deg);
  }
  20% {
    transform: scale(1.08) rotate(-7deg);
  }
  50% {
    transform: scale(1.05) rotate(7deg);
  }
  80% {
    transform: scale(1.02) rotate(-2deg);
  }
  100% {
    transform: scale(1) rotate(0deg);
  }
}
</style>
