<script>
export default { name: 'SendIcon' };
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
      <g :class="{ 'anim-plane': animating }">
        <path
          d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"
        />
      </g>
      <path
        :class="{ 'anim-trail': animating }"
        pathLength="1"
        d="M21.854 2.147l-10.94 10.939"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-plane {
  animation: send-plane 500ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-trail {
  stroke-dasharray: 1;
  stroke-dashoffset: 1;
  animation: send-trail 550ms ease forwards 100ms;
}
@keyframes send-plane {
  0%,
  100% {
    transform: translate(0, 0) scale(1);
  }
  50% {
    transform: translate(3px, -3px) scale(0.85);
  }
}
@keyframes send-trail {
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
