<script>
/**
 * Indicador de carregamento do widget.
 *
 * MOLDE dos primitivos de `widget/ui/` (bloco 2.01). O que este arquivo fixa,
 * e que os outros doze seguem:
 *
 *  1. nome `W…`, `name` declarado, um primitivo por arquivo;
 *  2. **nome acessível obrigatório por prop** (`label`, `required: true`) —
 *     spinner sem rótulo é invisível para leitor de tela, e o widget hoje tem
 *     11 controles mudos justamente por não haver onde exigir isso;
 *  3. `size` com `validator`, não `type` solto: valor errado reprova no
 *     desenvolvimento em vez de cair num default silencioso;
 *  4. **zero cor literal** — só classe tokenizada (`n-slate-10`, `n-strong`);
 *  5. **zero import de `dashboard/`** — o widget carrega o próprio grafo, e um
 *     import de lá arrasta CSS que o bloco 1.08 acabou de expulsar;
 *  6. `inheritAttrs: false` onde o root já recebe tudo que precisa.
 *
 * A régua que executa 4 e 5 nos treze é `specs/primitivosLint.spec.js`.
 */
const TAMANHOS = {
  tiny: 'w-spinner--tiny',
  small: 'w-spinner--small',
  medium: 'w-spinner--medium',
};

export default {
  name: 'WSpinner',
  inheritAttrs: false,
  props: {
    /** Nome acessível. Obrigatório: sem ele o leitor de tela anuncia nada. */
    label: { type: String, required: true },
    size: {
      type: String,
      default: 'small',
      validator: valor => Object.keys(TAMANHOS).includes(valor),
    },
  },
  computed: {
    classeTamanho() {
      return TAMANHOS[this.size] || TAMANHOS.small;
    },
  },
};
</script>

<template>
  <span
    class="w-spinner"
    :class="classeTamanho"
    role="status"
    :aria-label="label"
  />
</template>

<style scoped lang="scss">
@keyframes w-spinner-girar {
  to {
    transform: rotate(360deg);
  }
}

.w-spinner {
  @apply relative inline-block align-middle;

  &::before {
    @apply content-[''] box-border absolute top-1/2 left-1/2 rounded-full
      border-2 border-solid border-n-slate-10 border-t-n-strong
      animate-[w-spinner-girar_0.9s_linear_infinite];
  }

  &--tiny {
    @apply w-2.5 h-2.5;

    &::before {
      @apply w-2.5 h-2.5 -mt-1.5 -ml-1.5;
    }
  }

  &--small {
    @apply w-4 h-4;

    &::before {
      @apply w-4 h-4 -mt-2 -ml-2;
    }
  }

  &--medium {
    @apply w-6 h-6;

    &::before {
      @apply w-6 h-6 -mt-3 -ml-3;
    }
  }
}

// `prefers-reduced-motion` desliga a rotação: o papel do spinner é dizer "estou
// trabalhando", e isso o `role="status"` continua dizendo sem girar.
@media (prefers-reduced-motion: reduce) {
  .w-spinner::before {
    @apply animate-none;
  }
}
</style>
