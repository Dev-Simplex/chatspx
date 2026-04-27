<script>
export default { name: 'CloudDownloadIcon' };
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
      <path
        d="M4.393 15.269A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.436 8.284"
      />
      <g :class="{ 'anim-arrow': animating }">
        <path d="M12 13v8" />
        <path d="m8 17 4 4 4-4" />
      </g>
    </svg>
  </div>
</template>

<style scoped>
.anim-arrow {
  animation: cloud-dl-arrow 400ms cubic-bezier(0.68, -0.6, 0.32, 1.6) forwards;
}
@keyframes cloud-dl-arrow {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(3px);
  }
}
</style>
