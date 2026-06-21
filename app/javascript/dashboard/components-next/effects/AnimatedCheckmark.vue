<script setup>
// D8 / D-L6 — Checkmark de sucesso animado (molde animated-icons, 0 deps).
// SVG com `stroke-dashoffset` animado; `currentColor` herda a cor do pai =
// dark mode grátis (DD-10). Uso: feedback de sucesso ao assumir conversa.
defineProps({
  size: { type: Number, default: 24 },
});
</script>

<template>
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
    class="animated-checkmark"
    aria-hidden="true"
  >
    <circle cx="12" cy="12" r="10" class="checkmark-circle" />
    <path d="M7 12.5l3.5 3.5L17 9" class="checkmark-check" />
  </svg>
</template>

<style scoped>
.checkmark-circle {
  /* Circunferência: 2π × 10 ≈ 62.8 */
  stroke-dasharray: 63;
  stroke-dashoffset: 63;
  animation: checkmark-draw 0.5s ease-out forwards;
}

.checkmark-check {
  /* Comprimento do path do check ≈ 14.5 */
  stroke-dasharray: 15;
  stroke-dashoffset: 15;
  animation: checkmark-draw 0.3s ease-out 0.45s forwards;
}

@keyframes checkmark-draw {
  to {
    stroke-dashoffset: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .checkmark-circle,
  .checkmark-check {
    /* Sem animação: checkmark já desenhado (estático). */
    animation: none;
    stroke-dashoffset: 0;
  }
}
</style>
