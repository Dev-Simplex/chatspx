<script>
export default { name: 'PlusIcon' };
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
      <path d="M5 12h14" />
      <path d="M12 5v14" />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-plus 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes anim-plus {
  0% {
    transform: rotate(0deg) scale(1);
  }
  60% {
    transform: rotate(200deg) scale(0.9);
  }
  100% {
    transform: rotate(180deg) scale(1);
  }
}
</style>
