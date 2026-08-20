<script>
import { rotuloObrigatorio } from './rotulos';
/**
 * Botão que mostra só um ícone.
 *
 * `label` é `required` por decisão de projeto, não por estilo: um botão sem
 * texto visível não tem nome acessível nenhum, e é exatamente assim que se
 * chega aos 11 controles mudos que a matriz de snapshot mediu no widget.
 * Aqui não há como esquecer — sem `label` o componente não é usável.
 */
const TAMANHOS = { sm: 'w-icon-button--sm', md: 'w-icon-button--md' };

export default {
  name: 'WIconButton',
  props: {
    label: {
      type: String,
      required: true,
      validator: rotuloObrigatorio,
    },
    size: {
      type: String,
      default: 'md',
      validator: valor => Object.keys(TAMANHOS).includes(valor),
    },
    type: {
      type: String,
      default: 'button',
      validator: valor => ['button', 'submit', 'reset'].includes(valor),
    },
    disabled: { type: Boolean, default: false },
  },
  computed: {
    classeTamanho() {
      return TAMANHOS[this.size] || TAMANHOS.md;
    },
  },
};
</script>

<template>
  <button
    class="w-icon-button"
    :class="classeTamanho"
    :type="type"
    :disabled="disabled"
    :aria-label="label"
    :title="label"
  >
    <slot />
  </button>
</template>

<style scoped lang="scss">
.w-icon-button {
  @apply inline-flex items-center justify-center rounded-full cursor-pointer
    bg-transparent text-n-slate-11 transition-colors border-0;

  &:hover:not(:disabled) {
    @apply bg-n-alpha-2 text-n-slate-12;
  }

  &:disabled {
    @apply cursor-not-allowed opacity-60;
  }

  &:focus-visible {
    outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
    outline-offset: var(--w-focus-ring-offset);
  }

  &--sm {
    @apply w-8 h-8;
  }

  // 44px: alvo mínimo de toque em mobile.
  &--md {
    @apply w-11 h-11;
  }
}
</style>
