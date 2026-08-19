<script>
import { rotuloObrigatorio } from './rotulos';
import WIconButton from './WIconButton.vue';

/**
 * Cartão do teaser proativo.
 *
 * O botão de dispensar tem rótulo obrigatório por prop: é o controle que o
 * visitante mais precisa achar, e um "x" sem nome acessível é uma armadilha
 * para quem usa leitor de tela. O cartão inteiro NÃO é um botão — dispensar e
 * abrir são ações distintas e precisam de alvos distintos.
 */
export default {
  name: 'WTeaserCard',
  components: { WIconButton },
  props: {
    dismissLabel: {
      type: String,
      required: true,
      validator: rotuloObrigatorio,
    },
  },
  emits: ['dismiss', 'open'],
};
</script>

<template>
  <div class="w-teaser-card">
    <button class="w-teaser-card__corpo" type="button" @click="$emit('open')">
      <slot />
    </button>
    <WIconButton
      class="w-teaser-card__dispensar"
      size="sm"
      :label="dismissLabel"
      @click="$emit('dismiss')"
    >
      <slot name="dismiss-icon" />
    </WIconButton>
  </div>
</template>

<style scoped lang="scss">
.w-teaser-card {
  @apply relative flex items-start gap-2 rounded-2xl bg-n-solid-1 p-3
    border border-solid border-n-weak;

  &__corpo {
    @apply flex-1 text-left bg-transparent border-0 cursor-pointer p-0
      text-sm text-n-slate-12;

    &:focus-visible {
      outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
      outline-offset: var(--w-focus-ring-offset);
    }
  }
}
</style>
