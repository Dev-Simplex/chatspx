<script setup>
import { reactive, onMounted, ref, defineProps, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import WithLabel from 'v3/components/Form/WithLabel.vue';
import SectionLayout from 'dashboard/routes/dashboard/settings/account/components/SectionLayout.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'next/switch/Switch.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const store = useStore();
const labels = useMapGetter('labels/getLabels');

const isUpdating = ref(false);
const selectedBlocklistLabels = ref([]);
const currentLabel = ref('');
const selectedRequiredTags = ref([]);
const currentRequiredTag = ref('');

const state = reactive({
  npsSurveyEnabled: false,
  mode: 'auto',
  message: '',
  thankYouMessage: '',
  invalidResponseMessage: '',
  commentPromptMessage: '',
  expirationHours: 72,
  cooldownDays: 30,
  blocklistScope: 'both',
  minMessages: null,
  minDurationMinutes: null,
  requiredTags: [],
});

const modeOptions = [
  { label: t('INBOX_MGMT.NPS.MODE.AUTO', { default: 'Automático' }), value: 'auto' },
  { label: t('INBOX_MGMT.NPS.MODE.MANUAL', { default: 'Manual' }), value: 'manual' },
  { label: t('INBOX_MGMT.NPS.MODE.BOTH', { default: 'Ambos' }), value: 'both' },
];

const blocklistScopeOptions = [
  { label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.CONTACT', { default: 'Contato' }), value: 'contact' },
  { label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.CONVERSATION', { default: 'Conversa' }), value: 'conversation' },
  { label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.BOTH', { default: 'Ambos' }), value: 'both' },
];

const labelOptions = computed(() =>
  labels.value?.length
    ? labels.value
        .map(label => ({ label: label.title, value: label.title }))
        .filter(label => !selectedBlocklistLabels.value.includes(label.value))
    : []
);

const requiredTagOptions = computed(() =>
  labels.value?.length
    ? labels.value
        .map(label => ({ label: label.title, value: label.title }))
        .filter(label => !selectedRequiredTags.value.includes(label.value))
    : []
);

const initializeState = () => {
  if (!props.inbox) return;

  const { nps_survey_enabled, nps_config } = props.inbox;

  // Garantir que é um boolean explícito
  state.npsSurveyEnabled = nps_survey_enabled === true;

  if (!nps_config) {
    // Reset para valores padrão se não há config
    state.mode = 'auto';
    state.message = '';
    state.thankYouMessage = '';
    state.invalidResponseMessage = '';
    state.commentPromptMessage = '';
    state.expirationHours = 72;
    state.cooldownDays = 30;
    state.blocklistScope = 'both';
    state.minMessages = null;
    state.minDurationMinutes = null;
    state.requiredTags = [];
    selectedBlocklistLabels.value = [];
    selectedRequiredTags.value = [];
    return;
  }

  state.mode = nps_config.mode || 'auto';
  state.message = nps_config.message || '';
  state.thankYouMessage = nps_config.thank_you_message || '';
  state.invalidResponseMessage = nps_config.invalid_response_message || '';
  state.commentPromptMessage = nps_config.comment_prompt_message || '';
  state.expirationHours = nps_config.expiration_hours || 72;
  state.cooldownDays = nps_config.cooldown_days || 30;
  state.blocklistScope = nps_config.blocklist_scope || 'both';
  state.minMessages = nps_config.min_messages || null;
  state.minDurationMinutes = nps_config.min_duration_minutes || null;
  state.requiredTags = nps_config.required_tags || [];

  selectedBlocklistLabels.value = Array.isArray(nps_config.blocklist_labels)
    ? [...nps_config.blocklist_labels]
    : [];
  selectedRequiredTags.value = Array.isArray(nps_config.required_tags)
    ? [...nps_config.required_tags]
    : [];
};

onMounted(() => {
  initializeState();
  if (!labels.value?.length) store.dispatch('labels/get');
});

// Watch com deep para observar mudanças profundas, mas evitando reinicialização durante save
watch(
  () => props.inbox,
  () => {
    // Evitar reinicialização durante o processo de save
    if (isUpdating.value) return;
    initializeState();
  },
  { immediate: true }
);

const handleLabelSelect = value => {
  if (!value || selectedBlocklistLabels.value.includes(value)) {
    return;
  }

  selectedBlocklistLabels.value.push(value);
};

const removeLabel = label => {
  const index = selectedBlocklistLabels.value.indexOf(label);
  if (index !== -1) {
    selectedBlocklistLabels.value.splice(index, 1);
  }
};

const handleRequiredTagSelect = value => {
  if (!value || selectedRequiredTags.value.includes(value)) {
    return;
  }
  selectedRequiredTags.value.push(value);
};

const removeRequiredTag = tag => {
  const index = selectedRequiredTags.value.indexOf(tag);
  if (index !== -1) {
    selectedRequiredTags.value.splice(index, 1);
  }
};

const updateInbox = async attributes => {
  const payload = {
    id: props.inbox.id,
    formData: false,
    ...attributes,
  };

  return store.dispatch('inboxes/updateInbox', payload);
};

const saveSettings = async () => {
  try {
    isUpdating.value = true;

    const npsConfig = {
      mode: state.mode,
      message: state.message,
      thank_you_message: state.thankYouMessage,
      invalid_response_message: state.invalidResponseMessage,
      comment_prompt_message: state.commentPromptMessage,
      expiration_hours: state.expirationHours,
      cooldown_days: state.cooldownDays,
      blocklist_labels: selectedBlocklistLabels.value,
      blocklist_scope: state.blocklistScope,
      min_messages: state.minMessages,
      min_duration_minutes: state.minDurationMinutes,
      required_tags: selectedRequiredTags.value,
    };

    // Garantir que estamos enviando um boolean explícito
    const npsSurveyEnabledValue = state.npsSurveyEnabled === true;

    await updateInbox({
      nps_survey_enabled: npsSurveyEnabledValue,
      nps_config: npsConfig,
    });

    // Forçar atualização do estado local para garantir que está sincronizado
    state.npsSurveyEnabled = npsSurveyEnabledValue;

    useAlert(t('INBOX_MGMT.NPS.API.SUCCESS_MESSAGE', { default: 'Configurações NPS atualizadas com sucesso!' }));
  } catch (error) {
    console.error('Erro ao salvar configurações NPS:', error);
    useAlert(t('INBOX_MGMT.NPS.API.ERROR_MESSAGE', { default: 'Erro ao atualizar configurações NPS' }));
  } finally {
    // Aguardar um pouco antes de desabilitar para garantir que o store foi atualizado
    // e o watch não vai sobrescrever o estado
    setTimeout(() => {
      isUpdating.value = false;
    }, 300);
  }
};
</script>

<template>
  <div class="mx-8">
    <SectionLayout
      :title="$t('INBOX_MGMT.NPS.TITLE', { default: 'Net Promoter Score (NPS)' })"
      :description="$t('INBOX_MGMT.NPS.SUBTITLE', { default: 'Configure a pesquisa NPS para esta caixa de entrada' })"
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch v-model="state.npsSurveyEnabled" />
        </div>
      </template>

      <div class="grid gap-5">
        <WithLabel
          :label="$t('INBOX_MGMT.NPS.MODE.LABEL', { default: 'Modo de Disparo' })"
          name="mode"
        >
          <FilterSelect
            v-model="state.mode"
            :options="modeOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel :label="$t('INBOX_MGMT.NPS.MESSAGE.LABEL', { default: 'Mensagem da Pesquisa' })" name="message">
          <Editor
            v-model="state.message"
            :placeholder="$t('INBOX_MGMT.NPS.MESSAGE.PLACEHOLDER', { default: 'De 0 a 10, o quanto você recomendaria...' })"
            :max-length="500"
            class="w-full"
          />
        </WithLabel>

        <WithLabel :label="$t('INBOX_MGMT.NPS.THANK_YOU_MESSAGE.LABEL', { default: 'Mensagem de Agradecimento' })" name="thank_you_message">
          <Editor
            v-model="state.thankYouMessage"
            :placeholder="$t('INBOX_MGMT.NPS.THANK_YOU_MESSAGE.PLACEHOLDER', { default: 'Obrigado pela sua avaliação!' })"
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.INVALID_RESPONSE_MESSAGE.LABEL', { default: 'Mensagem para Resposta Inválida' })"
          name="invalid_response_message"
        >
          <Editor
            v-model="state.invalidResponseMessage"
            :placeholder="$t('INBOX_MGMT.NPS.INVALID_RESPONSE_MESSAGE.PLACEHOLDER', { default: 'Por favor, responda com um número de 0 a 10.' })"
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.COMMENT_PROMPT_MESSAGE.LABEL', { default: 'Mensagem de Prompt para Comentário' })"
          name="comment_prompt_message"
        >
          <Editor
            v-model="state.commentPromptMessage"
            :placeholder="$t('INBOX_MGMT.NPS.COMMENT_PROMPT_MESSAGE.PLACEHOLDER', { default: 'Gostaria de adicionar algum comentário?' })"
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.EXPIRATION_HOURS.LABEL', { default: 'Expiração (horas)' })"
          name="expiration_hours"
        >
          <input
            v-model.number="state.expirationHours"
            type="number"
            min="1"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.COOLDOWN_DAYS.LABEL', { default: 'Cooldown (dias)' })"
          name="cooldown_days"
        >
          <input
            v-model.number="state.cooldownDays"
            type="number"
            min="0"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.MIN_MESSAGES.LABEL', { default: 'Mínimo de Mensagens' })"
          name="min_messages"
        >
          <input
            v-model.number="state.minMessages"
            type="number"
            min="0"
            placeholder=""
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.MIN_DURATION_MINUTES.LABEL', { default: 'Duração Mínima (minutos)' })"
          name="min_duration_minutes"
        >
          <input
            v-model.number="state.minDurationMinutes"
            type="number"
            min="0"
            placeholder=""
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.BLOCKLIST.LABEL', { default: 'Etiquetas de Bloqueio' })"
          name="blocklist"
        >
          <div class="mb-4">
            <span class="inline-flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12">
              <NextButton
                v-for="label in selectedBlocklistLabels"
                :key="label"
                sm
                faded
                slate
                trailing-icon
                :label="label"
                icon="i-lucide-x"
                class="inline-flex shrink-0"
                @click="removeLabel(label)"
              />
              <FilterSelect
                v-model="currentLabel"
                :options="labelOptions"
                :label="$t('INBOX_MGMT.NPS.BLOCKLIST.SELECT_PLACEHOLDER', { default: 'Adicionar etiqueta' })"
                hide-label
                variant="faded"
                class="inline-flex shrink-0"
                @update:model-value="handleLabelSelect"
              />
            </span>
          </div>
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.LABEL', { default: 'Escopo do Bloqueio' })"
          name="blocklist_scope"
        >
          <FilterSelect
            v-model="state.blocklistScope"
            :options="blocklistScopeOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="$t('INBOX_MGMT.NPS.REQUIRED_TAGS.LABEL', { default: 'Etiquetas Obrigatórias' })"
          name="required_tags"
        >
          <div class="mb-4">
            <span class="inline-flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12">
              <NextButton
                v-for="tag in selectedRequiredTags"
                :key="tag"
                sm
                faded
                slate
                trailing-icon
                :label="tag"
                icon="i-lucide-x"
                class="inline-flex shrink-0"
                @click="removeRequiredTag(tag)"
              />
              <FilterSelect
                v-model="currentRequiredTag"
                :options="requiredTagOptions"
                :label="$t('INBOX_MGMT.NPS.REQUIRED_TAGS.SELECT_PLACEHOLDER', { default: 'Adicionar etiqueta' })"
                hide-label
                variant="faded"
                class="inline-flex shrink-0"
                @update:model-value="handleRequiredTagSelect"
              />
            </span>
          </div>
        </WithLabel>

        <div>
          <NextButton
            type="submit"
            :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE', { default: 'Atualizar' })"
            :is-loading="isUpdating"
            @click="saveSettings"
          />
        </div>
      </div>
    </SectionLayout>
  </div>
</template>
