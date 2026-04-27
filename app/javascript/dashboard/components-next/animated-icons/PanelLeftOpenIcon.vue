<script>
export default {
  name: 'PanelLeftOpenIcon',
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
        <rect width="18" height="18" x="3" y="3" rx="2" />
        <path d="M9 3v18m5-12l3 3l-3 3" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-panel-left-open 400ms cubic-bezier(0.34, 1.56, 0.64, 1)
    forwards;
}
@keyframes anim-panel-left-open {
  0%,
  100% {
    transform: rotate(0deg) translateY(0);
  }
  25% {
    transform: rotate(-5deg) translateY(-1px);
  }
  50% {
    transform: rotate(3deg) translateY(0);
  }
  75% {
    transform: rotate(-2deg) translateY(-0.5px);
  }
}
</style>
