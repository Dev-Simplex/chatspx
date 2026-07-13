<script setup>
// Editor de `send_location_request` (WhatsApp "pedir localização"). action_params = [{ body }].
//   • body: corpo da mensagem exibido acima do botão "Enviar localização" — obrigatório, aceita
//           Liquid ({{contact.name}}). A Meta anexa o botão automaticamente; a localização do
//           contato volta como uma resposta (location message).
// Formato EXATO consumido pelo Flows::ActionService#send_location_request: { body }.
// Componente controlado (padrão MessageConfig): reescreve action_params[0] a cada edição, sem
// estado local nem update fantasma ao abrir (o nó novo tem action_params vazio).
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

const BODY_MAX = 1024;

const body = computed({
  get() {
    const params = props.node.action_params;
    const first = Array.isArray(params) && params[0] ? params[0] : {};
    return first.body || '';
  },
  set(value) {
    emit('update', { action_params: [{ body: value }] });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-location-request">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.LOCATION_REQUEST.BODY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.LOCATION_REQUEST.VARIABLES_HINT')"
    >
      <textarea
        v-model="body"
        rows="4"
        :maxlength="BODY_MAX"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.LOCATION_REQUEST.BODY_PLACEHOLDER')
        "
        data-testid="config-location-request-body"
      />
    </ConfigField>

    <div
      class="flex items-start gap-2 px-3 py-2 text-xs border border-dashed rounded-lg text-n-slate-11 border-n-weak"
      data-testid="location-request-hint"
    >
      <span class="mt-1 rounded-full size-1.5 shrink-0 bg-n-slate-8" />
      {{ t('AUTOMATION.CANVAS.CONFIG.LOCATION_REQUEST.HINT') }}
    </div>
  </div>
</template>
