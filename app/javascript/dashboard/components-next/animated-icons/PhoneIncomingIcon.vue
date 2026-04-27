<script>
export default {
  name: 'PhoneIncomingIcon',
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
      <path
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M16 2v6h6m0-6l-6 6m-2.168 8.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233a14 14 0 0 0 6.392 6.384"
      />
    </svg>
  </div>
</template>

<style scoped>
svg.is-animating {
  animation: anim-phone-incoming 600ms cubic-bezier(0.34, 1.56, 0.64, 1)
    forwards;
}
@keyframes anim-phone-incoming {
  0%,
  100% {
    transform: rotate(0deg) translateY(0);
  }
  10% {
    transform: rotate(-15deg) translateY(-1px);
  }
  20% {
    transform: rotate(15deg) translateY(0);
  }
  30% {
    transform: rotate(-10deg) translateY(-1px);
  }
  40% {
    transform: rotate(10deg);
  }
  50% {
    transform: rotate(0deg);
  }
}
</style>
