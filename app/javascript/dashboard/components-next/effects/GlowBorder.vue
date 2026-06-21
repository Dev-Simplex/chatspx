<script setup>
import { computed } from 'vue';

// D8 / D-L6 — Glow Border: glow pulsante de box-shadow com token
// configurável (uso: tab de alerta "Não atribuídas", badges). Wrapper com
// slot; a cor vem de um token RGB do tema (_next-colors.scss), NUNCA hex
// (DD-10) — a tripla RGB permite compor alpha via `rgb(var(--token) / a)`.
const props = defineProps({
  // Nome da CSS var do token (tripla RGB), com ou sem `--`.
  colorToken: { type: String, default: '--ruby-9' },
  // Duração de um ciclo completo do pulso, em segundos.
  duration: { type: Number, default: 2 },
  // Raio da borda; `inherit` acompanha o border-radius do pai.
  borderRadius: { type: String, default: 'inherit' },
});

const normalizedToken = computed(() =>
  props.colorToken.startsWith('--') ? props.colorToken : `--${props.colorToken}`
);

const styleVars = computed(() => ({
  '--glow-border-rgb': `var(${normalizedToken.value})`,
  '--glow-border-duration': `${props.duration}s`,
  '--glow-border-radius': props.borderRadius,
}));
</script>

<template>
  <span class="glow-border" :style="styleVars">
    <slot />
  </span>
</template>

<style scoped>
.glow-border {
  display: inline-flex;
  border-radius: var(--glow-border-radius);
  animation: glow-border-pulse var(--glow-border-duration) ease-in-out
    infinite;
}

@keyframes glow-border-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgb(var(--glow-border-rgb) / 0.35);
  }

  50% {
    box-shadow: 0 0 8px 2px rgb(var(--glow-border-rgb) / 0.15);
  }
}

@media (prefers-reduced-motion: reduce) {
  .glow-border {
    /* Sem pulso: anel estático sutil preserva o affordance de alerta. */
    animation: none;
    box-shadow: 0 0 0 1px rgb(var(--glow-border-rgb) / 0.35);
  }
}
</style>
