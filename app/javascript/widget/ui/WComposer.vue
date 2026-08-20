<script>
import { rotuloObrigatorio } from './rotulos';
/**
 * Casca da área de composição: o campo e as ações.
 *
 * Primitivo sem regra de negócio — não sabe enviar mensagem, não fala com o
 * store. Quem liga isso é a tela, no bloco W2.9. O que ele garante é o que
 * hoje falha na §C.9: enviar e anexar deixam de ser mutuamente exclusivos
 * (são slots independentes) e o campo tem rótulo de verdade.
 */
export default {
  name: 'WComposer',
  inheritAttrs: false,
  props: {
    label: {
      type: String,
      required: true,
      validator: rotuloObrigatorio,
    },
    modelValue: { type: String, default: '' },
    placeholder: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'submit'],
  data() {
    return { compondo: false };
  },
  methods: {
    aoTeclar(evento) {
      // Enter envia, Shift+Enter quebra linha. `keydown`, não `keypress`:
      // `keypress` está obsoleto e não dispara para todas as teclas.
      if (evento.key !== 'Enter' || evento.shiftKey) return;

      // Enquanto o IME compõe, o Enter CONFIRMA o caractere — não envia.
      // Sem isto, quem digita "café" num teclado de celular em pt-BR manda
      // "caf" no meio da composição, e depois manda de novo: duas mensagens,
      // a primeira truncada.
      //
      // As três fontes são todas do evento nativo, nenhuma é timing:
      //  · `isComposing` do próprio keydown — o sinal canônico;
      //  · `keyCode === 229`, que é como vários navegadores marcam o Enter
      //    que confirma a composição;
      //  · a bandeira de `compositionstart`/`compositionend`, para o caso de
      //    o keydown chegar sem nenhum dos dois marcados.
      //
      // Isto é do PRIMITIVO por decisão de contrato: defesa que cada
      // consumidor precisa lembrar de repetir funciona só enquanto quem
      // escreve conhece a história.
      if (evento.isComposing || evento.keyCode === 229 || this.compondo) {
        return;
      }

      evento.preventDefault();
      this.$emit('submit');
    },
    aoIniciarComposicao() {
      this.compondo = true;
    },
    aoTerminarComposicao() {
      this.compondo = false;
    },
  },
};
</script>

<template>
  <div class="w-composer">
    <label class="sr-only" for="w-composer-campo">{{ label }}</label>
    <textarea
      id="w-composer-campo"
      class="w-composer__campo"
      rows="1"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :aria-label="label"
      v-bind="$attrs"
      @input="$emit('update:modelValue', $event.target.value)"
      @keydown="aoTeclar"
      @compositionstart="aoIniciarComposicao"
      @compositionend="aoTerminarComposicao"
    />
    <div class="w-composer__acoes">
      <slot name="actions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.w-composer {
  @apply flex items-end gap-2 w-full px-3 py-2 bg-n-background
    border-t border-solid border-n-weak;

  &__campo {
    @apply flex-1 resize-none bg-transparent text-base text-n-slate-12
      max-h-32 py-2 border-0;

    &:focus-visible {
      outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
      outline-offset: var(--w-focus-ring-offset);
    }
  }

  &__acoes {
    @apply flex items-center gap-1 shrink-0;
  }
}
</style>
