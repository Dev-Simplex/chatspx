<script setup>
// Editor de `send_message` e `add_private_note`. action_params = [conteúdo]. Textarea
// simples com suporte a variáveis Liquid ({{contact.name}}) — o backend resolve o Liquid.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const isPrivateNote = computed(
  () => props.node.action_name === 'add_private_note'
);

const content = computed({
  get() {
    const params = props.node.action_params;
    return Array.isArray(params) ? params[0] || '' : params || '';
  },
  set(value) {
    emit('update', { action_params: value ? [value] : [] });
  },
});
</script>

<template>
  <ConfigField
    :label="
      isPrivateNote
        ? t('AUTOMATION.CANVAS.CONFIG.MESSAGE.NOTE_LABEL')
        : t('AUTOMATION.CANVAS.CONFIG.MESSAGE.LABEL')
    "
    :hint="t('AUTOMATION.CANVAS.CONFIG.MESSAGE.VARIABLES_HINT')"
  >
    <textarea
      v-model="content"
      rows="5"
      class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
      :placeholder="
        isPrivateNote
          ? t('AUTOMATION.CANVAS.CONFIG.MESSAGE.NOTE_PLACEHOLDER')
          : t('AUTOMATION.CANVAS.CONFIG.MESSAGE.PLACEHOLDER')
      "
      data-testid="config-message-content"
    />
  </ConfigField>
</template>
