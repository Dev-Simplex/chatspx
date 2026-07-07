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
const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

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
  expirationHours: 72,
  cooldownHours: 24,
  blocklistScope: 'both',
  minMessages: null,
  minDurationMinutes: null,
  requiredTags: [],
  gptParseEnabled: false,
  thankYouPromoter: '',
  thankYouPassive: '',
  thankYouDetractor: '',
  detractorReopen: false,
  detractorAssigneeId: '',
  detractorTeamId: '',
  detractorLabel: '',
});

const modeOptions = [
  {
    label: t('INBOX_MGMT.NPS.MODE.AUTO', { default: 'Automático' }),
    value: 'auto',
  },
  {
    label: t('INBOX_MGMT.NPS.MODE.MANUAL', { default: 'Manual' }),
    value: 'manual',
  },
  { label: t('INBOX_MGMT.NPS.MODE.BOTH', { default: 'Ambos' }), value: 'both' },
];

const blocklistScopeOptions = [
  {
    label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.CONTACT', { default: 'Contato' }),
    value: 'contact',
  },
  {
    label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.CONVERSATION', {
      default: 'Conversa',
    }),
    value: 'conversation',
  },
  {
    label: t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.BOTH', { default: 'Ambos' }),
    value: 'both',
  },
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

const detractorAssigneeOptions = computed(() => [
  {
    label: t('INBOX_MGMT.NPS.DETRACTOR.ASSIGNEE_NONE', {
      default: 'Não atribuir',
    }),
    value: '',
  },
  ...(agents.value || []).map(agent => ({
    label: agent.name,
    value: agent.id,
  })),
]);

const detractorTeamOptions = computed(() => [
  {
    label: t('INBOX_MGMT.NPS.DETRACTOR.TEAM_NONE', { default: 'Nenhum' }),
    value: '',
  },
  ...(teams.value || []).map(team => ({
    label: team.name,
    value: team.id,
  })),
]);

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
    state.expirationHours = 72;
    state.cooldownHours = 24;
    state.blocklistScope = 'both';
    state.minMessages = null;
    state.minDurationMinutes = null;
    state.requiredTags = [];
    state.gptParseEnabled = false;
    state.thankYouPromoter = '';
    state.thankYouPassive = '';
    state.thankYouDetractor = '';
    state.detractorReopen = false;
    state.detractorAssigneeId = '';
    state.detractorTeamId = '';
    state.detractorLabel = '';
    selectedBlocklistLabels.value = [];
    selectedRequiredTags.value = [];
    return;
  }

  state.mode = nps_config.mode || 'auto';
  state.message = nps_config.message || '';
  state.thankYouMessage = nps_config.thank_you_message || '';
  state.invalidResponseMessage = nps_config.invalid_response_message || '';
  state.expirationHours = nps_config.expiration_hours || 72;
  // Cooldown em horas (prioridade); fallback: cooldown_days convertido para horas
  state.cooldownHours =
    nps_config.cooldown_hours ??
    (nps_config.cooldown_days != null && nps_config.cooldown_days !== ''
      ? Number(nps_config.cooldown_days) * 24
      : 24);
  state.blocklistScope = nps_config.blocklist_scope || 'both';
  state.minMessages = nps_config.min_messages || null;
  state.minDurationMinutes = nps_config.min_duration_minutes || null;
  state.requiredTags = nps_config.required_tags || [];
  state.gptParseEnabled = nps_config.gpt_parse_enabled === true;
  state.thankYouPromoter = nps_config.thank_you_promoter || '';
  state.thankYouPassive = nps_config.thank_you_passive || '';
  state.thankYouDetractor = nps_config.thank_you_detractor || '';
  state.detractorReopen = nps_config.detractor_reopen === true;
  state.detractorAssigneeId = nps_config.detractor_assignee_id ?? '';
  state.detractorTeamId = nps_config.detractor_team_id ?? '';
  state.detractorLabel = nps_config.detractor_label || '';

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
  if (!agents.value?.length) store.dispatch('agents/get');
  if (!teams.value?.length) store.dispatch('teams/get');
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
      expiration_hours: state.expirationHours,
      cooldown_hours: state.cooldownHours,
      blocklist_labels: selectedBlocklistLabels.value,
      blocklist_scope: state.blocklistScope,
      min_messages: state.minMessages,
      min_duration_minutes: state.minDurationMinutes,
      required_tags: selectedRequiredTags.value,
      gpt_parse_enabled: state.gptParseEnabled === true,
      thank_you_promoter: state.thankYouPromoter,
      thank_you_passive: state.thankYouPassive,
      thank_you_detractor: state.thankYouDetractor,
      detractor_reopen: state.detractorReopen === true,
      detractor_assignee_id: state.detractorAssigneeId || null,
      detractor_team_id: state.detractorTeamId || null,
      detractor_label: state.detractorLabel,
    };

    // Garantir que estamos enviando um boolean explícito
    const npsSurveyEnabledValue = state.npsSurveyEnabled === true;

    await updateInbox({
      nps_survey_enabled: npsSurveyEnabledValue,
      nps_config: npsConfig,
    });

    // Forçar atualização do estado local para garantir que está sincronizado
    state.npsSurveyEnabled = npsSurveyEnabledValue;

    useAlert(
      t('INBOX_MGMT.NPS.API.SUCCESS_MESSAGE', {
        default: 'Configurações NPS atualizadas com sucesso!',
      })
    );
  } catch {
    useAlert(
      t('INBOX_MGMT.NPS.API.ERROR_MESSAGE', {
        default: 'Erro ao atualizar configurações NPS',
      })
    );
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
      :title="
        $t('INBOX_MGMT.NPS.TITLE', { default: 'Net Promoter Score (NPS)' })
      "
      :description="
        $t('INBOX_MGMT.NPS.SUBTITLE', {
          default: 'Configure a pesquisa NPS para esta caixa de entrada',
        })
      "
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch v-model="state.npsSurveyEnabled" />
        </div>
      </template>

      <div class="grid gap-5">
        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.MODE.LABEL', { default: 'Modo de Disparo' })
          "
          name="mode"
        >
          <FilterSelect
            v-model="state.mode"
            :options="modeOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.MESSAGE.LABEL', {
              default: 'Mensagem da Pesquisa',
            })
          "
          name="message"
        >
          <Editor
            v-model="state.message"
            :placeholder="
              $t('INBOX_MGMT.NPS.MESSAGE.PLACEHOLDER', {
                default: 'De 0 a 10, o quanto você recomendaria...',
              })
            "
            :max-length="500"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.THANK_YOU_MESSAGE.LABEL', {
              default: 'Mensagem de Agradecimento',
            })
          "
          name="thank_you_message"
        >
          <Editor
            v-model="state.thankYouMessage"
            :placeholder="
              $t('INBOX_MGMT.NPS.THANK_YOU_MESSAGE.PLACEHOLDER', {
                default: 'Obrigado pela sua avaliação!',
              })
            "
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.THANK_YOU_PROMOTER.LABEL', {
              default: 'Agradecimento para promotores (9-10)',
            })
          "
          :help-message="
            $t('INBOX_MGMT.NPS.THANK_YOU_PROMOTER.HINT', {
              default:
                'Opcional. Se vazio, usa a mensagem de agradecimento genérica.',
            })
          "
          name="thank_you_promoter"
        >
          <Editor
            v-model="state.thankYouPromoter"
            :placeholder="
              $t('INBOX_MGMT.NPS.THANK_YOU_PROMOTER.PLACEHOLDER', {
                default: 'Que ótimo! Obrigado por recomendar a gente.',
              })
            "
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.THANK_YOU_PASSIVE.LABEL', {
              default: 'Agradecimento para neutros (7-8)',
            })
          "
          :help-message="
            $t('INBOX_MGMT.NPS.THANK_YOU_PASSIVE.HINT', {
              default:
                'Opcional. Se vazio, usa a mensagem de agradecimento genérica.',
            })
          "
          name="thank_you_passive"
        >
          <Editor
            v-model="state.thankYouPassive"
            :placeholder="
              $t('INBOX_MGMT.NPS.THANK_YOU_PASSIVE.PLACEHOLDER', {
                default: 'Obrigado pelo retorno! Vamos melhorar ainda mais.',
              })
            "
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.THANK_YOU_DETRACTOR.LABEL', {
              default: 'Agradecimento para detratores (0-6)',
            })
          "
          :help-message="
            $t('INBOX_MGMT.NPS.THANK_YOU_DETRACTOR.HINT', {
              default:
                'Opcional. Se vazio, usa a mensagem de agradecimento genérica.',
            })
          "
          name="thank_you_detractor"
        >
          <Editor
            v-model="state.thankYouDetractor"
            :placeholder="
              $t('INBOX_MGMT.NPS.THANK_YOU_DETRACTOR.PLACEHOLDER', {
                default: 'Sentimos muito. Vamos entrar em contato para ajudar.',
              })
            "
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.INVALID_RESPONSE_MESSAGE.LABEL', {
              default: 'Mensagem para Resposta Inválida',
            })
          "
          name="invalid_response_message"
        >
          <Editor
            v-model="state.invalidResponseMessage"
            :placeholder="
              $t('INBOX_MGMT.NPS.INVALID_RESPONSE_MESSAGE.PLACEHOLDER', {
                default: 'Por favor, responda com um número de 0 a 10.',
              })
            "
            :max-length="200"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.GPT_PARSE_ENABLED.LABEL', {
              default: 'Interpretar nota escrita por extenso (IA)',
            })
          "
          :help-message="
            $t('INBOX_MGMT.NPS.GPT_PARSE_ENABLED.HINT', {
              default:
                'Quando o cliente escreve a nota por extenso (ex.: \'dez\', \'nota nove\') e o reconhecimento automatico falha, usa IA apenas para extrair o numero. Nunca infere nota a partir de elogio/reclamacao.',
            })
          "
          name="gpt_parse_enabled"
        >
          <Switch v-model="state.gptParseEnabled" />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.EXPIRATION_HOURS.LABEL', {
              default: 'Expiração (horas)',
            })
          "
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
          :label="
            $t('INBOX_MGMT.NPS.COOLDOWN_HOURS.LABEL', {
              default: 'Cooldown (horas)',
            })
          "
          :help-message="
            $t('INBOX_MGMT.NPS.COOLDOWN_HOURS.HINT', {
              default:
                'Ex.: 24 = 1 dia. Vários agentes podem atender no mesmo dia sem enviar NPS em toda resolução.',
            })
          "
          name="cooldown_hours"
        >
          <input
            v-model.number="state.cooldownHours"
            type="number"
            min="0"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.MIN_MESSAGES.LABEL', {
              default: 'Mínimo de Mensagens',
            })
          "
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
          :label="
            $t('INBOX_MGMT.NPS.MIN_DURATION_MINUTES.LABEL', {
              default: 'Duração Mínima (minutos)',
            })
          "
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
          :label="
            $t('INBOX_MGMT.NPS.BLOCKLIST.LABEL', {
              default: 'Etiquetas de Bloqueio',
            })
          "
          name="blocklist"
        >
          <div class="mb-4">
            <span
              class="inline-flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12"
            >
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
                :label="
                  $t('INBOX_MGMT.NPS.BLOCKLIST.SELECT_PLACEHOLDER', {
                    default: 'Adicionar etiqueta',
                  })
                "
                hide-label
                variant="faded"
                class="inline-flex shrink-0"
                @update:model-value="handleLabelSelect"
              />
            </span>
          </div>
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.BLOCKLIST_SCOPE.LABEL', {
              default: 'Escopo do Bloqueio',
            })
          "
          name="blocklist_scope"
        >
          <FilterSelect
            v-model="state.blocklistScope"
            :options="blocklistScopeOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.REQUIRED_TAGS.LABEL', {
              default: 'Etiquetas Obrigatórias',
            })
          "
          name="required_tags"
        >
          <div class="mb-4">
            <span
              class="inline-flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12"
            >
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
                :label="
                  $t('INBOX_MGMT.NPS.REQUIRED_TAGS.SELECT_PLACEHOLDER', {
                    default: 'Adicionar etiqueta',
                  })
                "
                hide-label
                variant="faded"
                class="inline-flex shrink-0"
                @update:model-value="handleRequiredTagSelect"
              />
            </span>
          </div>
        </WithLabel>

        <div class="pt-2">
          <h4 class="text-sm font-medium text-n-slate-12 mb-1">
            {{
              $t('INBOX_MGMT.NPS.DETRACTOR.SECTION_TITLE', {
                default: 'Detrator (0-6) -> follow-up humano',
              })
            }}
          </h4>
        </div>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.DETRACTOR.REOPEN.LABEL', {
              default: 'Reabrir e encaminhar detratores para follow-up',
            })
          "
          name="detractor_reopen"
        >
          <Switch v-model="state.detractorReopen" />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.DETRACTOR.ASSIGNEE.LABEL', {
              default: 'Atribuir detrator ao agente',
            })
          "
          name="detractor_assignee_id"
        >
          <FilterSelect
            v-model="state.detractorAssigneeId"
            :options="detractorAssigneeOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.DETRACTOR.TEAM.LABEL', {
              default: 'Atribuir detrator ao time',
            })
          "
          name="detractor_team_id"
        >
          <FilterSelect
            v-model="state.detractorTeamId"
            :options="detractorTeamOptions"
            class="w-full"
          />
        </WithLabel>

        <WithLabel
          :label="
            $t('INBOX_MGMT.NPS.DETRACTOR.LABEL.LABEL', {
              default: 'Adicionar etiqueta ao detrator',
            })
          "
          name="detractor_label"
        >
          <input
            v-model="state.detractorLabel"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.NPS.DETRACTOR.LABEL.PLACEHOLDER', {
                default: 'detrator',
              })
            "
            class="w-full"
          />
        </WithLabel>

        <div>
          <NextButton
            type="submit"
            :label="
              $t('INBOX_MGMT.SETTINGS_POPUP.UPDATE', { default: 'Atualizar' })
            "
            :is-loading="isUpdating"
            @click="saveSettings"
          />
        </div>
      </div>
    </SectionLayout>
  </div>
</template>
