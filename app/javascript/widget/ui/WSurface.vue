<script>
/** Superfície: fundo, raio e borda tokenizados. Sem regra de negócio. */
const ELEVACOES = {
  flat: 'w-surface--flat',
  raised: 'w-surface--raised',
  sunken: 'w-surface--sunken',
};

export default {
  name: 'WSurface',
  props: {
    as: { type: String, default: 'div' },
    elevation: {
      type: String,
      default: 'flat',
      validator: valor => Object.keys(ELEVACOES).includes(valor),
    },
  },
  computed: {
    classeElevacao() {
      return ELEVACOES[this.elevation] || ELEVACOES.flat;
    },
  },
};
</script>

<template>
  <component :is="as" class="w-surface" :class="classeElevacao">
    <slot />
  </component>
</template>

<style scoped lang="scss">
.w-surface {
  @apply rounded-xl;

  &--flat {
    @apply bg-n-background;
  }

  &--raised {
    @apply bg-n-solid-1 border border-solid border-n-weak;
  }

  &--sunken {
    @apply bg-n-alpha-1;
  }
}
</style>
