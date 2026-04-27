<script>
export default { name: 'Trash2Icon' };
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
      <g :class="{ 'anim-lid': animating }">
        <path d="M3 6h18" />
        <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
      </g>
      <g :class="{ 'anim-body': animating }">
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
        <path d="M10 11v6" />
        <path d="M14 11v6" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-lid {
  transform-origin: center 6px;
  animation: trash-lid 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-body {
  transform-origin: center bottom;
  animation: trash-body 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes trash-lid {
  0%,
  100% {
    transform: translateY(0) rotate(0deg);
  }
  30% {
    transform: translateY(-3px) rotate(-6deg);
  }
  60% {
    transform: translateY(-1px) rotate(2deg);
  }
}
@keyframes trash-body {
  0%,
  100% {
    transform: rotate(0deg);
  }
  25% {
    transform: rotate(-2deg);
  }
  50% {
    transform: rotate(2deg);
  }
  75% {
    transform: rotate(-1deg);
  }
}
</style>
