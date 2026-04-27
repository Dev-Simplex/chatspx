<script>
export default {
  name: 'CalendarX2Icon',
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
        d="M8 2v4m8-4v4m5 7V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8M3 10h18m-4 12l5-5m-5 0l5 5"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-calendar-x2 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-calendar-x2 {
  0%,
  100% {
    transform: translateY(0) rotate(0);
  }
  30% {
    transform: translateY(-3px) rotate(-2deg);
  }
  60% {
    transform: translateY(-1px) rotate(1deg);
  }
}
</style>
