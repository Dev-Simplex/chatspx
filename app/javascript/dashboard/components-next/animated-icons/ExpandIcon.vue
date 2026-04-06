<script>
export default { name: 'ExpandIcon' };
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
      <!-- Top-left corner -->
      <g :class="{ 'anim-tl': animating }">
        <path d="M3 8V3h5" />
        <path d="M9 9 3 3" />
      </g>
      <!-- Top-right corner -->
      <g :class="{ 'anim-tr': animating }">
        <path d="M21 8V3h-5" />
        <path d="m15 9 6-6" />
      </g>
      <!-- Bottom-left corner -->
      <g :class="{ 'anim-bl': animating }">
        <path d="M3 16v5h5" />
        <path d="M3 21l6-6" />
      </g>
      <!-- Bottom-right corner -->
      <g :class="{ 'anim-br': animating }">
        <path d="m15 15 6 6" />
        <path d="M16 21h5v-5" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-tl {
  animation: expand-tl 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-tr {
  animation: expand-tr 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-bl {
  animation: expand-bl 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-br {
  animation: expand-br 400ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes expand-tl {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(-2px, -2px);
  }
}
@keyframes expand-tr {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(2px, -2px);
  }
}
@keyframes expand-bl {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(-2px, 2px);
  }
}
@keyframes expand-br {
  0%,
  100% {
    transform: translate(0, 0);
  }
  50% {
    transform: translate(2px, 2px);
  }
}
</style>
