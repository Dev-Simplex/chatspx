<script>
/**
 * Placeholder de carregamento.
 *
 * `aria-hidden` sempre: quem anuncia o carregamento é o `WSpinner` com
 * `role="status"`. Skeleton lido em voz alta vira ruído de caixas vazias.
 */
export default {
  name: 'WSkeleton',
  props: {
    lines: {
      type: Number,
      default: 1,
      validator: valor => Number.isInteger(valor) && valor > 0,
    },
    rounded: { type: Boolean, default: false },
  },
};
</script>

<template>
  <div class="w-skeleton" aria-hidden="true">
    <span
      v-for="linha in lines"
      :key="linha"
      class="w-skeleton__linha"
      :class="{ 'w-skeleton__linha--round': rounded }"
    />
  </div>
</template>

<style scoped lang="scss">
.w-skeleton {
  @apply flex flex-col gap-2 w-full;

  &__linha {
    @apply block h-3 w-full rounded bg-n-alpha-2;

    animation: w-skeleton-pulsar 1.4s ease-in-out infinite;

    &--round {
      @apply rounded-full;
    }
  }
}

@keyframes w-skeleton-pulsar {
  0%,
  100% {
    opacity: 0.55;
  }

  50% {
    opacity: 1;
  }
}

@media (prefers-reduced-motion: reduce) {
  .w-skeleton__linha {
    animation: none;
  }
}
</style>
