<script>
export default { name: 'SettingsIcon' };
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
    >
      <path
        :class="{ 'anim-gear': animating }"
        d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0a2.34 2.34 0 0 0 3.319 1.915a2.34 2.34 0 0 1 2.33 4.033a2.34 2.34 0 0 0 0 3.831a2.34 2.34 0 0 1-2.33 4.033a2.34 2.34 0 0 0-3.319 1.915a2.34 2.34 0 0 1-4.659 0a2.34 2.34 0 0 0-3.32-1.915a2.34 2.34 0 0 1-2.33-4.033a2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"
      />
      <circle
        :class="{ 'anim-gear-center': animating }"
        cx="12"
        cy="12"
        r="3"
      />
    </svg>
  </div>
</template>

<style scoped>
.anim-gear {
  transform-origin: 12px 12px;
  animation: gear-rotate 600ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
.anim-gear-center {
  transform-origin: 12px 12px;
  animation: gear-center 600ms cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
}
@keyframes gear-rotate {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(180deg);
  }
}
@keyframes gear-center {
  0% {
    transform: rotate(0deg) scale(1);
  }
  50% {
    transform: rotate(-90deg) scale(0.8);
  }
  100% {
    transform: rotate(-180deg) scale(1);
  }
}
</style>
