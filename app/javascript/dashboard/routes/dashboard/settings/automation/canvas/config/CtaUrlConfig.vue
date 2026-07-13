<script setup>
// Editor de `send_cta_url` (WhatsApp botão de link / call-to-action URL).
// action_params = [{ body, button_text, url, header, footer }].
//   • body:        corpo da mensagem — obrigatório, máx 1024, aceita Liquid ({{contact.name}}).
//   • button_text: rótulo do botão (display_text da Meta) — obrigatório.
//   • url:         URL http(s) aberta ao tocar no botão — obrigatória.
//   • header/footer: opcionais (title no topo / small print embaixo).
// Formato EXATO consumido pelo Flows::ActionService#send_cta_url:
//   { body, button_text, url, header, footer }
// Componente controlado (padrão SendInteractiveConfig/MessageConfig): cada edição reconstrói
// action_params[0] inteiro a partir dos valores atuais — sem estado local/hydration, sem
// emitir update fantasma ao abrir (o nó novo tem action_params vazio e só persiste ao digitar).
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

// Limites oficiais Meta (também validados no backend — última linha de defesa é o canal).
const BODY_MAX = 1024;
const BUTTON_TEXT_MAX = 20;
const HEADER_MAX = 60;
const FOOTER_MAX = 60;

const config = computed(() => {
  const params = props.node.action_params;
  const first = Array.isArray(params) && params[0] ? params[0] : {};
  return {
    body: '',
    button_text: '',
    url: '',
    header: '',
    footer: '',
    ...first,
  };
});

// Reescreve action_params[0] no formato EXATO { body, button_text, url, header, footer }.
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

// URL válida = vazia (deixa o "obrigatório" cobrir) ou http(s). Só sinaliza; o backend rejeita.
const urlIsValid = computed(() => {
  const value = config.value.url || '';
  return !value || /^https?:\/\//i.test(value);
});

const urlMessage = computed(() => {
  if (!config.value.url)
    return t('AUTOMATION.CANVAS.CONFIG.CTA_URL.URL_REQUIRED');
  if (!urlIsValid.value)
    return t('AUTOMATION.CANVAS.CONFIG.CTA_URL.URL_INVALID');
  return '';
});
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-cta-url">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.BODY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.VARIABLES_HINT')"
    >
      <textarea
        v-model="body"
        rows="4"
        :maxlength="BODY_MAX"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.BODY_PLACEHOLDER')"
        data-testid="config-cta-url-body"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.BUTTON_TEXT_LABEL')"
    >
      <Input
        :model-value="config.button_text"
        size="sm"
        :maxlength="BUTTON_TEXT_MAX"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.CTA_URL.BUTTON_TEXT_PLACEHOLDER')
        "
        :message="
          config.button_text
            ? ''
            : t('AUTOMATION.CANVAS.CONFIG.CTA_URL.BUTTON_TEXT_REQUIRED')
        "
        :message-type="config.button_text ? 'info' : 'error'"
        data-testid="config-cta-url-button-text"
        @update:model-value="patch({ button_text: $event })"
      />
    </ConfigField>

    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.URL_LABEL')">
      <Input
        :model-value="config.url"
        size="sm"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.URL_PLACEHOLDER')"
        :message="urlMessage"
        :message-type="config.url && urlIsValid ? 'info' : 'error'"
        data-testid="config-cta-url-url"
        @update:model-value="patch({ url: $event })"
      />
    </ConfigField>

    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.HEADER_LABEL')">
      <Input
        :model-value="config.header"
        size="sm"
        :maxlength="HEADER_MAX"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.HEADER_PLACEHOLDER')"
        data-testid="config-cta-url-header"
        @update:model-value="patch({ header: $event })"
      />
    </ConfigField>

    <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.FOOTER_LABEL')">
      <Input
        :model-value="config.footer"
        size="sm"
        :maxlength="FOOTER_MAX"
        :placeholder="t('AUTOMATION.CANVAS.CONFIG.CTA_URL.FOOTER_PLACEHOLDER')"
        data-testid="config-cta-url-footer"
        @update:model-value="patch({ footer: $event })"
      />
    </ConfigField>
  </div>
</template>
