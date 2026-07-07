<script setup>
// Editor de `send_template` (WhatsApp Cloud). action_params = [{ name, language, content,
// processed_params }] — a mesma forma que o Flows::ActionService#send_template consome.
//
// Fluxo: escolher inbox WhatsApp → escolher template aprovado → reusar o
// WhatsAppTemplateParser (prévia do balão + inputs de variáveis) → "Aplicar" persiste as
// variáveis. A inbox NÃO é persistida (em runtime usa-se a inbox da conversa); serve só
// para listar templates no editor.
//
// TODO(reuso): o WhatsAppTemplateParser não aceita `processed_params` inicial via prop —
// ao reabrir um nó salvo, os campos de variável começam vazios (os valores salvos são
// preservados até um novo "Aplicar"). Pré-preencher exigiria estender o parser upstream.
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const whatsappInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const getTemplates = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

const selectedInboxId = ref(null);
const selectedTemplate = ref(null);

const bodyOf = template =>
  template?.components?.find(component => component.type === 'BODY')?.text ||
  '';

const inboxOptions = computed(() =>
  whatsappInboxes.value.map(inbox => ({ id: inbox.id, name: inbox.name }))
);

const templates = computed(() =>
  selectedInboxId.value ? getTemplates.value(selectedInboxId.value) : []
);

const templateOptions = computed(() =>
  templates.value.map(template => ({ id: template.id, name: template.name }))
);

const inboxModel = computed({
  get() {
    return (
      inboxOptions.value.find(opt => opt.id === selectedInboxId.value) || null
    );
  },
  set(value) {
    selectedInboxId.value = value ? value.id : null;
    selectedTemplate.value = null;
  },
});

const templateModel = computed({
  get() {
    if (!selectedTemplate.value) return null;
    return (
      templateOptions.value.find(opt => opt.id === selectedTemplate.value.id) ||
      null
    );
  },
  set(value) {
    const template = templates.value.find(tpl => tpl.id === value?.id) || null;
    selectedTemplate.value = template;
    if (template) {
      // Persiste o básico já na seleção (nó válido mesmo sem variáveis).
      emit('update', {
        action_params: [
          {
            name: template.name,
            language: template.language,
            content: bodyOf(template),
            processed_params: {},
          },
        ],
      });
    }
  },
});

const onApply = payload => {
  const params = payload.templateParams || {};
  emit('update', {
    action_params: [
      {
        name: params.name,
        language: params.language,
        content: payload.message,
        processed_params: params.processed_params || {},
      },
    ],
  });
};

// Reabertura de nó salvo: localiza o template pelo nome/idioma entre as inboxes WhatsApp.
const hydrateFromNode = () => {
  selectedInboxId.value = null;
  selectedTemplate.value = null;
  const stored = props.node.action_params?.[0];
  if (!stored?.name) return;
  whatsappInboxes.value.some(inbox => {
    const match = getTemplates
      .value(inbox.id)
      .find(
        template =>
          template.name === stored.name &&
          (!stored.language || template.language === stored.language)
      );
    if (match) {
      selectedInboxId.value = inbox.id;
      selectedTemplate.value = match;
      return true;
    }
    return false;
  });
};

onMounted(hydrateFromNode);
watch(() => props.node.id, hydrateFromNode);
</script>

<template>
  <div class="flex flex-col gap-4">
    <p
      v-if="!inboxOptions.length"
      class="p-3 text-sm rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.NO_INBOXES') }}
    </p>
    <template v-else>
      <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.INBOX_LABEL')">
        <SingleSelect
          v-model="inboxModel"
          :options="inboxOptions"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.INBOX_PLACEHOLDER')
          "
        />
      </ConfigField>

      <ConfigField
        v-if="selectedInboxId"
        :label="t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.TEMPLATE_LABEL')"
      >
        <SingleSelect
          v-model="templateModel"
          :options="templateOptions"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.TEMPLATE_PLACEHOLDER')
          "
        />
        <p v-if="!templateOptions.length" class="mt-1 text-xs text-n-slate-10">
          {{ t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.NO_TEMPLATES') }}
        </p>
      </ConfigField>

      <WhatsAppTemplateParser
        v-if="selectedTemplate"
        :key="selectedTemplate.id"
        :template="selectedTemplate"
        @send-message="onApply"
      >
        <template #actions="{ sendMessage, disabled }">
          <NextButton
            blue
            sm
            class="w-full"
            :label="t('AUTOMATION.CANVAS.CONFIG.TEMPLATE.APPLY')"
            :disabled="disabled"
            @click="sendMessage"
          />
        </template>
      </WhatsAppTemplateParser>
    </template>
  </div>
</template>
