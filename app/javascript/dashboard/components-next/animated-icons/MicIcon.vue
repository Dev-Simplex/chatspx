<script>
export default { name: 'MicIcon' };
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
      <rect
        :class="{ 'anim-capsule': animating }"
        width="6"
        height="13"
        x="9"
        y="2"
        rx="3"
      />
      <g :class="{ 'anim-base': animating }">
        <path d="M19 12v2a7 7 0 0 1-14 0v-2" />
        <path d="M12 19v3" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-capsule {
  transform-origin: 12px 8px;
  animation: mic-capsule 600ms ease-in-out forwards;
}
.anim-base {
  transform-origin: 12px 19px;
  animation: mic-base 600ms ease-in-out forwards 100ms;
}
@keyframes mic-capsule {
  0%,
  100% {
    transform: translateY(0);
  }
  25% {
    transform: translateY(-3px);
  }
  50% {
    transform: translateY(0);
  }
  75% {
    transform: translateY(-2px);
  }
}
@keyframes mic-base {
  0%,
  100% {
    transform: scaleX(1);
    opacity: 1;
  }
  50% {
    transform: scaleX(1.1);
    opacity: 0.7;
  }
}
</style>
