<script>
import { rotuloObrigatorio } from './rotulos';
/**
 * Campo de formulário com rótulo REALMENTE associado.
 *
 * O `for`/`id` é gerado aqui porque essa é a diferença entre um rótulo que o
 * leitor de tela liga ao campo e um texto solto ao lado dele. A medição do axe
 * nos tipos ricos do widget acusou `label` como violação crítica — é este o
 * componente que impede a próxima.
 */
let sequencia = 0;

export default {
  name: 'WField',
  inheritAttrs: false,
  props: {
    label: {
      type: String,
      required: true,
      validator: rotuloObrigatorio,
    },
    modelValue: { type: String, default: '' },
    id: { type: String, default: '' },
    type: { type: String, default: 'text' },
    error: { type: String, default: '' },
    hint: { type: String, default: '' },
    required: { type: Boolean, default: false },
  },
  emits: ['update:modelValue'],
  data() {
    sequencia += 1;
    return { idInterno: `w-field-${sequencia}` };
  },
  computed: {
    idCampo() {
      return this.id || this.idInterno;
    },
    idErro() {
      return `${this.idCampo}-erro`;
    },
    idHint() {
      return `${this.idCampo}-hint`;
    },
    // O campo aponta para a mensagem de erro e para a ajuda; sem isso o leitor
    // de tela anuncia "inválido" sem dizer o motivo.
    descritores() {
      return [this.hint ? this.idHint : null, this.error ? this.idErro : null]
        .filter(Boolean)
        .join(' ');
    },
  },
};
</script>

<template>
  <div class="w-field">
    <label class="w-field__rotulo" :for="idCampo">
      {{ label }}
      <span v-if="required" class="w-field__obrigatorio" aria-hidden="true">
        *
      </span>
    </label>
    <input
      :id="idCampo"
      class="w-field__campo"
      :class="{ 'w-field__campo--erro': error }"
      :type="type"
      :value="modelValue"
      :required="required"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="descritores || undefined"
      v-bind="$attrs"
      @input="$emit('update:modelValue', $event.target.value)"
    />
    <p v-if="hint" :id="idHint" class="w-field__hint">{{ hint }}</p>
    <p v-if="error" :id="idErro" class="w-field__erro">{{ error }}</p>
  </div>
</template>

<style scoped lang="scss">
.w-field {
  @apply flex flex-col gap-1 w-full;

  &__rotulo {
    @apply text-sm font-medium text-n-slate-12;
  }

  &__obrigatorio {
    @apply text-n-ruby-11;
  }

  &__campo {
    @apply w-full rounded-lg border border-solid border-n-weak bg-n-background
      px-3 py-2 text-base text-n-slate-12 min-h-11;

    &:focus-visible {
      outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
      outline-offset: var(--w-focus-ring-offset);
    }

    &--erro {
      @apply border-n-ruby-8;
    }
  }

  &__hint {
    @apply text-xs text-n-slate-11;
  }

  &__erro {
    @apply text-xs text-n-ruby-11;
  }
}
</style>
