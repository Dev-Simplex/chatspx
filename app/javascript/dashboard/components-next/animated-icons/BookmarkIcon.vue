<script>
export default { name: 'BookmarkIcon' };
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
        :class="{ 'anim-bookmark': animating }"
        d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-bookmark {
  transform-origin: 12px 12px;
  animation: bookmark-bounce 600ms ease-out forwards;
}
@keyframes bookmark-bounce {
  0% {
    transform: scaleX(1) scaleY(1);
  }
  20% {
    transform: scaleX(0.9) scaleY(1.3);
  }
  40% {
    transform: scaleX(1.1) scaleY(0.9);
  }
  60% {
    transform: scaleX(0.95) scaleY(1.05);
  }
  80% {
    transform: scaleX(1.02) scaleY(0.98);
  }
  100% {
    transform: scaleX(1) scaleY(1);
  }
}
</style>
