<script>
import { rotuloLimpo } from './rotulos';
import WSpinner from './WSpinner.vue';

/** Botão com texto. Para botão só de ícone use `WIconButton`. */
const VARIANTES = {
  primary: 'w-button--primary',
  secondary: 'w-button--secondary',
  ghost: 'w-button--ghost',
};
const TAMANHOS = { sm: 'w-button--sm', md: 'w-button--md' };

export default {
  name: 'WButton',
  components: { WSpinner },
  props: {
    variant: {
      type: String,
      default: 'primary',
      validator: valor => Object.keys(VARIANTES).includes(valor),
    },
    size: {
      type: String,
      default: 'md',
      validator: valor => Object.keys(TAMANHOS).includes(valor),
    },
    // `button` explícito: o default do HTML dentro de <form> é `submit`, e é
    // assim que um botão qualquer passa a enviar o formulário sem querer.
    type: {
      type: String,
      default: 'button',
      validator: valor => ['button', 'submit', 'reset'].includes(valor),
    },
    disabled: { type: Boolean, default: false },
    loading: { type: Boolean, default: false },
    // Rótulo do estado de carregamento — anunciado enquanto `loading`.
    loadingLabel: { type: String, default: '', validator: rotuloLimpo },
  },
  computed: {
    classes() {
      return [VARIANTES[this.variant], TAMANHOS[this.size]];
    },
  },
};
</script>

<template>
  <button
    class="w-button"
    :class="classes"
    :type="type"
    :disabled="disabled || loading"
    :aria-busy="loading ? 'true' : undefined"
  >
    <WSpinner v-if="loading" size="tiny" :label="loadingLabel" />
    <slot />
  </button>
</template>

<style scoped lang="scss">
.w-button {
  @apply inline-flex items-center justify-center gap-2 rounded-xl font-medium
    transition-colors cursor-pointer border border-solid border-transparent;

  &:disabled {
    @apply cursor-not-allowed opacity-60;
  }

  // Foco visível de verdade: o anel do token, não o outline do navegador, que
  // some contra fundo escuro.
  &:focus-visible {
    outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
    outline-offset: var(--w-focus-ring-offset);
  }

  &--sm {
    @apply text-sm px-3 py-1.5 min-h-8;
  }

  // 44px: alvo mínimo de toque.
  &--md {
    @apply text-base px-4 py-2 min-h-11;
  }

  &--primary {
    background-color: var(--w-brand);
    color: var(--w-on-brand);

    &:hover:not(:disabled) {
      background-color: var(--w-brand-hover);
    }

    &:active:not(:disabled) {
      background-color: var(--w-brand-active);
    }
  }

  &--secondary {
    @apply bg-n-alpha-2 text-n-slate-12 border-n-weak;

    &:hover:not(:disabled) {
      @apply bg-n-alpha-3;
    }
  }

  &--ghost {
    @apply bg-transparent text-n-slate-11;

    &:hover:not(:disabled) {
      @apply bg-n-alpha-2;
    }
  }
}
</style>
