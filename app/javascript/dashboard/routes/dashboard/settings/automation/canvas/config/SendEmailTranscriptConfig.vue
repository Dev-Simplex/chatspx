<script setup>
// Editor de `send_email_transcript`. action_params = [emails] — UMA string com os destinatários
// separados por vírgula (o backend faz `emails[0].gsub(/\s+/,'').split(',')`). Cada endereço passa
// por parse_email_variables (aceita variáveis). Gated por account.email_transcript_enabled? e pelo
// rate-limit de e-mail. Ver ActionService#send_email_transcript (action_service.rb:79-91).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const emails = computed({
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
    :label="t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TRANSCRIPT.LABEL')"
    :hint="t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TRANSCRIPT.HINT')"
  >
    <Input
      v-model="emails"
      size="sm"
      :placeholder="
        t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TRANSCRIPT.PLACEHOLDER')
      "
      data-testid="config-email-transcript"
    />
  </ConfigField>
</template>
