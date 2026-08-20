<script>
export default {
  name: 'WTypingDots',
};
</script>

<template>
  <!-- Substitui o `typing.gif` de 19.296 B por três pontos em CSS.
       `aria-hidden` no grupo de pontos e o texto de verdade em `.sr-only`: o
       GIF anterior carregava a mensagem no `alt`, o que funcionava, mas um
       indicador que muda de estado precisa ser anunciado como estado, não como
       imagem. `role="status"` anuncia uma vez, com `polite`, sem interromper. -->
  <div class="w-typing" role="status" :aria-label="$t('A11Y.AGENT_TYPING')">
    <span class="w-typing__dot" aria-hidden="true" />
    <span class="w-typing__dot" aria-hidden="true" />
    <span class="w-typing__dot" aria-hidden="true" />
  </div>
</template>

<style lang="scss" scoped>
.w-typing {
  @apply flex items-center gap-1 h-4 px-0.5;
}

.w-typing__dot {
  @apply w-1.5 h-1.5 rounded-full bg-n-slate-10;
  // A curva é a padrão da casa, e a animação anima OPACIDADE e TRANSFORM —
  // ambas compostas na GPU, sem custo de layout.
  animation: w-typing-bounce 1.2s var(--w-ease-standard) infinite;

  &:nth-child(2) {
    animation-delay: 0.15s;
  }

  &:nth-child(3) {
    animation-delay: 0.3s;
  }
}

@keyframes w-typing-bounce {
  0%,
  60%,
  100% {
    opacity: 0.45;
    transform: translateY(0);
  }

  30% {
    opacity: 1;
    transform: translateY(-3px);
  }
}

// Movimento é preferência, não decoração obrigatória. Com `reduce` os pontos
// param de saltar e passam a pulsar só em opacidade — o indicador continua
// legível para quem precisa saber que o agente está digitando, sem deslocamento
// na tela. Um `animation: none` aqui apagaria a informação.
@media (prefers-reduced-motion: reduce) {
  .w-typing__dot {
    animation: w-typing-fade 1.6s steps(2, end) infinite;
    transform: none;
  }

  @keyframes w-typing-fade {
    0%,
    100% {
      opacity: 0.45;
    }

    50% {
      opacity: 1;
    }
  }
}
</style>
