<script setup>
// Editor de `send_webhook_event`. action_params = [url]. O backend enfileira um WebhookJob com o
// `@conversation.webhook_data` + o nome do evento, para `webhook_url[0]`. Ver
// Flows::ActionService#send_webhook_event (action_service.rb:121-124). Diferente do `http_request`,
// é uma notificação fire-and-forget (paridade com a automação legada) — sem headers/body/SSRF aqui.
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

const url = computed({
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
    :label="t('AUTOMATION.CANVAS.CONFIG.SEND_WEBHOOK_EVENT.LABEL')"
    :hint="t('AUTOMATION.CANVAS.CONFIG.SEND_WEBHOOK_EVENT.HINT')"
  >
    <Input
      v-model="url"
      size="sm"
      :placeholder="
        t('AUTOMATION.CANVAS.CONFIG.SEND_WEBHOOK_EVENT.PLACEHOLDER')
      "
      data-testid="config-webhook-event"
    />
  </ConfigField>
</template>
