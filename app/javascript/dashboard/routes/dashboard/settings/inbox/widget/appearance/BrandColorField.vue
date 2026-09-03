<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ContrastReadout from './ContrastReadout.vue';
import { isValidHex } from '../composables/useContrast';

/**
 * A cor da marca: seletor, campo hex e o medidor logo abaixo.
 *
 * O campo hex aceita o que o cliente digitar e so RECLAMA quando o valor nao e
 * um hex — nao corrige sozinho, nao bloqueia. Enquanto o valor for invalido, o
 * medidor diz que nao consegue calcular, em vez de exibir numero inventado.
 */
const props = defineProps({
  modelValue: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const isValid = computed(() => isValidHex(props.modelValue));

const update = value => emit('update:modelValue', value);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-start gap-3">
      <ColorPicker :model-value="modelValue" @update:model-value="update" />
      <Input
        :model-value="modelValue"
        class="w-32"
        data-testid="brand-hex"
        :aria-label="t('INBOX_WIDGET.APPEARANCE.BRAND_COLOR.HEX_LABEL')"
        :message="
          isValid ? '' : t('INBOX_WIDGET.APPEARANCE.BRAND_COLOR.INVALID')
        "
        :message-type="isValid ? 'info' : 'error'"
        @update:model-value="update"
      />
    </div>

    <ContrastReadout :color="modelValue" />
  </div>
</template>
