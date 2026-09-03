<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { CONDITION_OPERATORS, OPERATORS_WITHOUT_VALUE } from './preChatModel';

/**
 * A condicional de um campo: "só pergunte isto se aquilo".
 *
 * Só campo de etapa ANTERIOR entra em `sources` (§B.4.4) — quem monta a lista é
 * o `preChatModel`, e não este componente, porque a regra é cobrada por aceite
 * e regra dentro de componente só se verifica montando a tela inteira.
 *
 * Sem `E`/`OU` aninhado nesta entrega, por decisão da §B.4.4: condicional
 * aninhada em construtor visual é uma tela inteira por si só.
 */
const props = defineProps({
  modelValue: { type: Object, default: null },
  sources: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const fieldOptions = computed(() =>
  props.sources.map(field => ({
    value: field.name,
    label: field.label || field.name,
  }))
);

const operatorOptions = computed(() =>
  CONDITION_OPERATORS.map(operator => ({
    value: operator,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.OPERATORS.${operator.toUpperCase()}`
    ),
  }))
);

const needsValue = computed(
  () => !OPERATORS_WITHOUT_VALUE.includes(props.modelValue?.operator)
);

const patch = change =>
  emit('update:modelValue', { ...(props.modelValue ?? {}), ...change });

const add = () =>
  emit('update:modelValue', {
    field: props.sources[0]?.name ?? '',
    operator: 'filled',
    value: '',
  });

const remove = () => emit('update:modelValue', null);
</script>

<template>
  <div class="flex flex-col gap-2">
    <p
      v-if="!sources.length"
      class="text-sm text-n-slate-11"
      data-testid="condition-no-sources"
    >
      {{ t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.NO_SOURCES') }}
    </p>
    <NextButton
      v-else-if="!modelValue"
      faded
      slate
      sm
      data-testid="condition-add"
      :disabled="disabled"
      :label="t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.ADD')"
      @click="add"
    />
    <div
      v-else
      class="flex flex-wrap items-end gap-2"
      data-testid="condition-row"
    >
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.FIELD') }}
        <Select
          :model-value="modelValue.field"
          data-testid="condition-field"
          :options="fieldOptions"
          :disabled="disabled"
          @update:model-value="patch({ field: $event })"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.OPERATOR') }}
        <Select
          :model-value="modelValue.operator"
          data-testid="condition-operator"
          :options="operatorOptions"
          :disabled="disabled"
          @update:model-value="patch({ operator: $event })"
        />
      </label>
      <label
        v-if="needsValue"
        class="flex flex-col gap-1 text-sm text-n-slate-11"
      >
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.VALUE') }}
        <Input
          :model-value="modelValue.value ?? ''"
          data-testid="condition-value"
          :disabled="disabled"
          @update:model-value="patch({ value: $event })"
        />
      </label>
      <NextButton
        faded
        ruby
        sm
        data-testid="condition-remove"
        :disabled="disabled"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.REMOVE')"
        @click="remove"
      />
    </div>
  </div>
</template>
