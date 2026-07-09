<script setup>
// Editor de `send_attachment`. action_params = [blob_id] — id de um ActiveStorage::Blob que o
// backend anexa a uma mensagem outgoing (Flows::ActionService#send_attachment, action_service.rb:110).
// Reusa o widget de upload da automação legada (AutomationFileInput → automations/uploadAttachment),
// que emite exatamente [blob_id] — o mesmo shape que o backend lê em `ActiveStorage::Blob.where(id:)`.
//
// LIMITAÇÃO F1 (documentada): o backend só envia se o FLOW já tiver arquivos anexados
// (`return unless @flow.files.attached?`, action_service.rb:112), mas o flows_controller AINDA NÃO
// persiste blobs no flow (o automation_rules_controller faz `@rule.files.attach(blob)`; o
// flows_controller#flow_permit não inclui blobs). Enquanto essa via não é ligada (F2), o nó coleta
// o blob_id correto porém a ação é no-op em runtime. O editor existe para paridade visual/UX do
// canvas (evita o card "sem parâmetros") e já grava o parâmetro no formato final.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomationFileInput from 'dashboard/components/widgets/AutomationFileInput.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

// O canvas não carrega os metadados do arquivo (só o blob_id fica no nó); quando já há um valor,
// mostramos um rótulo genérico "anexado" em vez do nome real do arquivo.
const hasBlob = computed(() => {
  const params = props.node.action_params;
  return Array.isArray(params) && Boolean(params[0]);
});

const onFile = value => {
  emit('update', { action_params: Array.isArray(value) ? value : [] });
};
</script>

<template>
  <ConfigField
    :label="t('AUTOMATION.CANVAS.CONFIG.SEND_ATTACHMENT.LABEL')"
    :hint="t('AUTOMATION.CANVAS.CONFIG.SEND_ATTACHMENT.HINT')"
  >
    <AutomationFileInput
      :initial-file-name="
        hasBlob ? t('AUTOMATION.CANVAS.CONFIG.SEND_ATTACHMENT.ATTACHED') : ''
      "
      @update:model-value="onFile"
    />
  </ConfigField>
</template>
