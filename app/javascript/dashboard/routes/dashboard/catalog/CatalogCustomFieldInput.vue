<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// Um controle por campo personalizado do item, conforme o tipo da definição. O valor sai sempre
// como texto (ou booleano, na caixa de seleção): quem converte para o tipo do campo é o servidor.
const props = defineProps({
  definicao: {
    type: Object,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const valor = defineModel({ type: [String, Boolean], default: '' });

const { t } = useI18n();

const TIPOS_DE_INPUT = { number: 'number', date: 'date', link: 'url' };

const tipo = computed(() => props.definicao.attribute_display_type);
const rotulo = computed(() => props.definicao.attribute_display_name);
const tipoDoInput = computed(() => TIPOS_DE_INPUT[tipo.value] || 'text');

// O valor já gravado entra na lista mesmo que a opção tenha sido tirada do campo depois: sem
// isso o seletor abriria em branco escondendo um valor que continua salvo no item.
const opcoes = computed(() => {
  const valores = props.definicao.attribute_values || [];
  const todas =
    valor.value && !valores.includes(valor.value)
      ? [valor.value, ...valores]
      : valores;

  return [
    { value: '', label: t('CATALOG_MGMT.FORM.CUSTOM_FIELDS.EMPTY_OPTION') },
    ...todas.map(opcao => ({ value: opcao, label: opcao })),
  ];
});
</script>

<template>
  <div
    class="flex flex-col gap-1"
    :data-testid="`campo-personalizado-${definicao.attribute_key}`"
  >
    <label
      v-if="tipo === 'checkbox'"
      class="flex items-center gap-2 cursor-pointer min-h-10 text-n-slate-12 text-body-main"
    >
      <Checkbox v-model="valor" :disabled="disabled" />
      {{ rotulo }}
    </label>
    <template v-else-if="tipo === 'list'">
      <span class="mb-0.5 text-heading-3 text-n-slate-12">{{ rotulo }}</span>
      <Select v-model="valor" :options="opcoes" :disabled="disabled" />
    </template>
    <Input
      v-else
      v-model="valor"
      :type="tipoDoInput"
      :step="tipo === 'number' ? 'any' : undefined"
      :label="rotulo"
      :placeholder="
        tipo === 'currency'
          ? $t('CATALOG_MGMT.FORM.FIELDS.PRICE_PLACEHOLDER')
          : ''
      "
      :disabled="disabled"
    />
    <span
      v-if="definicao.hidden"
      class="flex items-center gap-1 text-n-slate-10 text-label-small"
    >
      <span class="i-lucide-eye-off size-3" />
      {{ $t('CATALOG_MGMT.FORM.CUSTOM_FIELDS.INTERNAL_HINT') }}
    </span>
  </div>
</template>
