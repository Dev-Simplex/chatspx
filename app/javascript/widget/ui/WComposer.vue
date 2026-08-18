<script>
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
    label: { type: String, required: true },
    modelValue: { type: String, default: '' },
    placeholder: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'submit'],
  methods: {
    aoTeclar(evento) {
      // Enter envia, Shift+Enter quebra linha. `keydown`, não `keypress`:
      // `keypress` está obsoleto e não dispara para todas as teclas.
      if (evento.key === 'Enter' && !evento.shiftKey) {
        evento.preventDefault();
        this.$emit('submit');
      }
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
