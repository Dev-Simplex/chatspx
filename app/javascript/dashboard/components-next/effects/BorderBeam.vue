<script setup>
import { computed } from 'vue';

// D8 / D-L6 — Border Beam (port Inspira UI doc v1, CSS puro, 0 deps).
// Feixe de luz percorrendo a borda do elemento pai (que deve ser
// `position: relative`). Cores SEMPRE via tokens `rgb(var(--token))`,
// nunca hex (DD-10).
const props = defineProps({
  // Duração de uma volta completa do feixe, em segundos.
  duration: { type: Number, default: 6 },
  // Espessura da borda percorrida pelo feixe, em px.
  size: { type: Number, default: 1.5 },
  // Cores do feixe — defaults em tokens do tema (dark mode automático).
  colorFrom: { type: String, default: 'rgb(var(--blue-9))' },
  colorTo: { type: String, default: 'rgb(var(--iris-9))' },
  // Raio da borda; `inherit` acompanha o border-radius do pai.
  borderRadius: { type: String, default: 'inherit' },
});

const styleVars = computed(() => ({
  '--border-beam-duration': `${props.duration}s`,
  '--border-beam-size': `${props.size}px`,
  '--border-beam-color-from': props.colorFrom,
  '--border-beam-color-to': props.colorTo,
  '--border-beam-radius': props.borderRadius,
}));
</script>

<template>
  <span class="border-beam" aria-hidden="true" :style="styleVars" />
</template>

<style scoped>
/*
 * Registro global da custom property animável (Baseline 2024).
 * Fallback SEM `@property`: o navegador não interpola `--border-beam-angle`,
 * o conic-gradient fica parado = borda estática colorida (design §9.2).
 */
@property --border-beam-angle {
  syntax: '<angle>';
  initial-value: 0deg;
  inherits: false;
}

.border-beam {
  pointer-events: none;
  position: absolute;
  inset: 0;
  border-radius: var(--border-beam-radius);
  /* O padding define a espessura visível; a máscara dupla (content-box x
     border-box) recorta o gradiente para mostrar APENAS a borda. */
  padding: var(--border-beam-size);
  background: conic-gradient(
    from var(--border-beam-angle),
    transparent 0deg,
    var(--border-beam-color-from) 40deg,
    var(--border-beam-color-to) 80deg,
    transparent 120deg
  );
  /* `white` aqui é só máscara de alpha (qualquer cor opaca serve) — não é
     cor de tema, logo não entra na regra de tokens. */
  -webkit-mask:
    linear-gradient(white 0 0) content-box,
    linear-gradient(white 0 0);
  -webkit-mask-composite: xor;
  mask:
    linear-gradient(white 0 0) content-box,
    linear-gradient(white 0 0);
  mask-composite: exclude;
  animation: border-beam-spin var(--border-beam-duration) linear infinite;
}

@keyframes border-beam-spin {
  to {
    --border-beam-angle: 360deg;
  }
}

@media (prefers-reduced-motion: reduce) {
  .border-beam {
    /* Sem animação: feixe vira borda estática colorida. */
    animation: none;
  }
}
</style>
