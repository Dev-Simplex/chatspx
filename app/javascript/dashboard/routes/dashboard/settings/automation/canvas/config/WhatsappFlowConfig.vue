<script setup>
// Editor de `send_whatsapp_flow` (WhatsApp Flow interactive NATIVO da Meta — formulário).
// action_params = [{ flow_id, cta, body, header, footer, screen, flow_action }].
//   • flow_id:     ID do Flow publicado no WhatsApp Manager — obrigatório.
//   • cta:         rótulo do botão que abre o Flow (flow_cta) — obrigatório.
//   • body:        corpo da mensagem acima do botão — obrigatório, aceita Liquid.
//   • flow_action: 'navigate' (abre a 1ª tela) | 'data_exchange' (aciona o endpoint). Default navigate.
//   • header/footer/screen: opcionais (title / small print / id da tela inicial).
// Formato EXATO consumido pelo Flows::WhatsappFlowAction#send_whatsapp_flow:
//   { flow_id, cta, body, header, footer, screen, flow_action }
// (o flow_token é gerado no backend — não é campo do editor.)
// Componente controlado (padrão SendInteractiveConfig): reescreve action_params[0] a cada edição,
// sem estado local/hydration nem update fantasma ao abrir (nó novo tem action_params vazio).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
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
const CTA_MAX = 30; // flow_cta da Meta
const HEADER_MAX = 60;
const FOOTER_MAX = 60;
const FLOW_ACTIONS = ['navigate', 'data_exchange'];

const config = computed(() => {
  const params = props.node.action_params;
  const first = Array.isArray(params) && params[0] ? params[0] : {};
  return {
    flow_id: '',
    cta: '',
    body: '',
    header: '',
    footer: '',
    screen: '',
    flow_action: 'navigate',
    ...first,
  };
});

// Reescreve action_params[0] no formato EXATO { flow_id, cta, body, header, footer, screen, flow_action }.
const patch = partial => {
  emit('update', { action_params: [{ ...config.value, ...partial }] });
};

const body = computed({
  get() {
    return config.value.body || '';
  },
  set(value) {
    patch({ body: value });
  },
});

const flowActionOptions = computed(() => [
  {
    id: 'navigate',
    name: t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.ACTION_NAVIGATE'),
  },
  {
    id: 'data_exchange',
    name: t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.ACTION_DATA_EXCHANGE'),
  },
]);

const flowActionModel = computed({
  get() {
    const current = FLOW_ACTIONS.includes(config.value.flow_action)
      ? config.value.flow_action
      : 'navigate';
    return (
      flowActionOptions.value.find(opt => opt.id === current) ||
      flowActionOptions.value[0]
    );
  },
  set(value) {
    patch({ flow_action: value?.id || 'navigate' });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-whatsapp-flow">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FLOW_ID_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FLOW_ID_HINT')"
    >
      <Input
        :model-value="config.flow_id"
        size="sm"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FLOW_ID_PLACEHOLDER')
        "
        :message="
          config.flow_id
            ? ''
            : t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FLOW_ID_REQUIRED')
        "
        :message-type="config.flow_id ? 'info' : 'error'"
        data-testid="config-whatsapp-flow-id"
        @update:model-value="patch({ flow_id: $event })"
      />
    </ConfigField>

    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.CTA_LABEL')">
      <Input
        :model-value="config.cta"
        size="sm"
        :maxlength="CTA_MAX"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.CTA_PLACEHOLDER')
        "
        :message="
          config.cta
            ? ''
            : t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.CTA_REQUIRED')
        "
        :message-type="config.cta ? 'info' : 'error'"
        data-testid="config-whatsapp-flow-cta"
        @update:model-value="patch({ cta: $event })"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.BODY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.VARIABLES_HINT')"
    >
      <textarea
        v-model="body"
        rows="4"
        :maxlength="BODY_MAX"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.BODY_PLACEHOLDER')
        "
        data-testid="config-whatsapp-flow-body"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.ACTION_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.ACTION_HINT')"
    >
      <SingleSelect
        v-model="flowActionModel"
        disable-search
        disable-deselect
        :options="flowActionOptions"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.SCREEN_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.SCREEN_HINT')"
    >
      <Input
        :model-value="config.screen"
        size="sm"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.SCREEN_PLACEHOLDER')
        "
        data-testid="config-whatsapp-flow-screen"
        @update:model-value="patch({ screen: $event })"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.HEADER_LABEL')"
    >
      <Input
        :model-value="config.header"
        size="sm"
        :maxlength="HEADER_MAX"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.HEADER_PLACEHOLDER')
        "
        data-testid="config-whatsapp-flow-header"
        @update:model-value="patch({ header: $event })"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FOOTER_LABEL')"
    >
      <Input
        :model-value="config.footer"
        size="sm"
        :maxlength="FOOTER_MAX"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.WHATSAPP_FLOW.FOOTER_PLACEHOLDER')
        "
        data-testid="config-whatsapp-flow-footer"
        @update:model-value="patch({ footer: $event })"
      />
    </ConfigField>
  </div>
</template>
