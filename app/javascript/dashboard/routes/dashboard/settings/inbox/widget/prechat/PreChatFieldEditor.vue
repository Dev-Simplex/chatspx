<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { applyMask, validateFieldValue } from 'shared/helpers/brMasks';
import ConditionEditor from './ConditionEditor.vue';
import { MASK_NAMES, VALIDATOR_NAMES } from './preChatModel';

/**
 * O editor de um campo do pré-chat.
 *
 * VALIDAÇÃO NO BLUR, NUNCA A CADA TECLA (§B.4.4 e aceite 26): a mensagem só
 * aparece depois que o campo perde o foco. Erro que pisca enquanto a pessoa
 * ainda está digitando o próprio e-mail é anti-padrão conhecido — e aqui vale
 * duas vezes, porque a prévia deste editor mostra ao administrador exatamente
 * o que o visitante vai viver.
 */
const props = defineProps({
  field: { type: Object, required: true },
  sources: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update', 'remove']);

const { t } = useI18n();

const labelTouched = ref(false);
const previewValue = ref('');
const previewTouched = ref(false);

/**
 * Campo padrão (`emailAddress`, `fullName`, `phoneNumber`) tem tipo travado: o
 * `type` deles casa com o atributo do contato do outro lado. Trocar `email` por
 * `text` no `emailAddress` quebraria a identificação do contato, e a tela não
 * deve deixar isso acontecer por descuido.
 */
const isStandard = computed(() => props.field.field_type === 'standard');

const maskOptions = computed(() => [
  { value: '', label: t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.NONE') },
  ...MASK_NAMES.map(mask => ({
    value: mask,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(`INBOX_WIDGET.PRE_CHAT_FORM.MASKS.${mask.toUpperCase()}`),
  })),
]);

const validatorOptions = computed(() => [
  { value: '', label: t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.NONE') },
  ...VALIDATOR_NAMES.map(validator => ({
    value: validator,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `INBOX_WIDGET.PRE_CHAT_FORM.VALIDATORS.${validator.toUpperCase()}`
    ),
  })),
]);

const labelError = computed(() =>
  labelTouched.value && !String(props.field.label ?? '').trim()
    ? t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.LABEL_REQUIRED')
    : ''
);

const previewVerdict = computed(() =>
  validateFieldValue(previewValue.value, {
    validator: props.field.validator,
    required: props.field.required,
  })
);

/**
 * A mensagem da prévia: o `error_message` que o cliente escreveu ganha do texto
 * padrão — é para isso que o campo existe. Sem ele, o texto padrão do código do
 * validador.
 */
const previewMessage = computed(() => {
  if (!previewTouched.value || previewVerdict.value.valid) return '';
  return (
    String(props.field.error_message ?? '').trim() ||
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    t(`INBOX_WIDGET.PRE_CHAT_FORM.VALIDATION.${previewVerdict.value.code}`)
  );
});

/** Anti-lixo é aviso, não barreira (§B.4.3) — e a cor do campo tem de dizer
 * isso, senão a tela promete um bloqueio que o widget não aplica. */
const previewMessageType = computed(() =>
  previewVerdict.value.severity === 'warning' ? 'info' : 'error'
);

const patch = change => emit('update', change);

const onPreviewInput = value => {
  previewValue.value = props.field.mask
    ? applyMask(value, props.field.mask)
    : value;
};
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
  >
    <div class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">{{
          field.name
        }}</span>
        <span class="text-xs text-n-slate-11">{{ field.type }}</span>
      </div>
      <NextButton
        faded
        ruby
        sm
        data-testid="field-remove"
        :disabled="disabled"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.REMOVE_FIELD')"
        @click="$emit('remove')"
      />
    </div>

    <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <Input
        :model-value="field.label ?? ''"
        data-testid="field-label"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.LABEL')"
        :disabled="disabled"
        :message="labelError"
        :message-type="labelError ? 'error' : 'info'"
        @update:model-value="patch({ label: $event })"
        @blur="labelTouched = true"
      />
      <Input
        :model-value="field.placeholder ?? ''"
        data-testid="field-placeholder"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.PLACEHOLDER')"
        :disabled="disabled"
        @update:model-value="patch({ placeholder: $event })"
      />
      <Input
        :model-value="field.help_text ?? ''"
        data-testid="field-help-text"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.HELP_TEXT')"
        :disabled="disabled"
        @update:model-value="patch({ help_text: $event })"
      />
      <Input
        :model-value="field.error_message ?? ''"
        data-testid="field-error-message"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.ERROR_MESSAGE')"
        :disabled="disabled"
        @update:model-value="patch({ error_message: $event })"
      />
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.MASK') }}
        <Select
          :model-value="field.mask ?? ''"
          data-testid="field-mask"
          :options="maskOptions"
          :disabled="disabled"
          @update:model-value="patch({ mask: $event })"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.VALIDATOR') }}
        <Select
          :model-value="field.validator ?? ''"
          data-testid="field-validator"
          :options="validatorOptions"
          :disabled="disabled"
          @update:model-value="patch({ validator: $event })"
        />
      </label>
    </div>

    <div class="flex items-center gap-2">
      <Switch
        :model-value="Boolean(field.required)"
        data-testid="field-required"
        :disabled="disabled"
        @update:model-value="patch({ required: $event })"
      />
      <span class="text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.REQUIRED') }}
      </span>
      <span v-if="isStandard" class="text-xs text-n-slate-10">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.STANDARD_TYPE_LOCKED') }}
      </span>
    </div>

    <ConditionEditor
      :model-value="field.show_if ?? null"
      :sources="sources"
      :disabled="disabled"
      @update:model-value="patch({ show_if: $event })"
    />

    <div class="flex flex-col gap-1 pt-2 border-t border-n-weak">
      <span class="text-xs text-n-slate-11">
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.PREVIEW_HINT') }}
      </span>
      <Input
        :model-value="previewValue"
        data-testid="field-preview"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.EDITOR.PREVIEW')"
        :placeholder="field.placeholder ?? ''"
        :message="previewMessage"
        :message-type="previewMessageType"
        @update:model-value="onPreviewInput"
        @blur="previewTouched = true"
      />
    </div>
  </div>
</template>
