<script>
export default { name: 'MailCheckIcon' };
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
      <g :class="{ 'anim-mail': animating }">
        <path d="M22 13V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v12c0 1.1.9 2 2 2h8" />
        <path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" />
      </g>
      <path
        :class="{ 'anim-check': animating }"
        pathLength="1"
        d="m16 18 2 2 4-4"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-mail {
  animation: mail-float 500ms ease forwards;
}
.anim-check {
  stroke-dasharray: 1;
  stroke-dashoffset: 1;
  animation: mail-check-draw 400ms ease forwards 200ms;
}
@keyframes mail-float {
  0%,
  100% {
    transform: translateY(0);
  }
  40% {
    transform: translateY(-2px);
  }
}
@keyframes mail-check-draw {
  0% {
    stroke-dashoffset: 1;
    opacity: 0;
  }
  30% {
    opacity: 1;
  }
  100% {
    stroke-dashoffset: 0;
    opacity: 1;
  }
}
</style>
