<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useAlert } from 'dashboard/composables';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

// Kit próprio de Agentes IA (sem componentes legados).
import AiProviderCard from 'dashboard/components-next/agents-ui/AiProviderCard.vue';
import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiBadge from 'dashboard/components-next/agents-ui/AiBadge.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiListGroup from 'dashboard/components-next/agents-ui/AiListGroup.vue';
import AiListRow from 'dashboard/components-next/agents-ui/AiListRow.vue';
import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';
import AiToggle from 'dashboard/components-next/agents-ui/AiToggle.vue';

const { t } = useI18n();
const { captainEnabled } = useCaptain();

const captainConfigStore = useCaptainConfigStore();
const { uiFlags, llmConnection, anthropicConnection, features } =
  storeToRefs(captainConfigStore);

const isLoading = computed(() => uiFlags.value.isFetching);

// Cabeçalho de seção estilo iOS (lista agrupada).
const SECTION_LABEL =
  'px-1 pb-2 text-[11px] font-semibold tracking-wider uppercase text-n-slate-10';

const openaiApiKey = ref('');
const anthropicApiKey = ref('');
const isUpdatingOpenai = ref(false);
const isUpdatingAnthropic = ref(false);
const activeProvider = ref('openai');

const PROVIDERS = [
  {
    id: 'openai',
    name: 'OpenAI',
    desc: 'GPT-4o, o3…',
    color: '#10a37f',
    icon: 'i-lucide-sparkles',
  },
  {
    id: 'anthropic',
    name: 'Anthropic',
    desc: 'Claude, Fable…',
    color: '#d97757',
    icon: 'i-lucide-sparkles',
  },
  {
    id: 'google',
    name: 'Google',
    desc: 'Em breve',
    color: '#4285f4',
    icon: 'i-lucide-sliders-horizontal',
    disabled: true,
  },
];

const isOpenAiConfigured = computed(() =>
  Boolean(llmConnection.value?.configured)
);
const isAnthropicConfigured = computed(() =>
  Boolean(anthropicConnection.value?.configured)
);

const activeName = computed(
  () => PROVIDERS.find(p => p.id === activeProvider.value)?.name || ''
);
const activeConfigured = computed(() =>
  activeProvider.value === 'openai'
    ? isOpenAiConfigured.value
    : isAnthropicConfigured.value
);
const activeMasked = computed(() =>
  activeProvider.value === 'openai'
    ? llmConnection.value?.maskedApiKey || null
    : anthropicConnection.value?.maskedApiKey || null
);
const activeUpdating = computed(() =>
  activeProvider.value === 'openai'
    ? isUpdatingOpenai.value
    : isUpdatingAnthropic.value
);
const activeKey = computed({
  get: () =>
    activeProvider.value === 'openai'
      ? openaiApiKey.value
      : anthropicApiKey.value,
  set: v => {
    if (activeProvider.value === 'openai') openaiApiKey.value = v;
    else anthropicApiKey.value = v;
  },
});
const canSave = computed(
  () => activeKey.value.trim().length > 0 && !activeUpdating.value
);
const canRemove = computed(
  () => activeConfigured.value && !activeUpdating.value
);

const selectProvider = p => {
  if (p.disabled) return;
  activeProvider.value = p.id;
};

async function persist(payload, updatingRef, clearRef) {
  updatingRef.value = true;
  try {
    await captainConfigStore.updatePreferences(payload);
    if (clearRef) clearRef.value = '';
    useAlert(t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.SUCCESS'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.ERROR')
    );
  } finally {
    updatingRef.value = false;
  }
}

const handleSave = () => {
  if (!canSave.value) return;
  if (activeProvider.value === 'openai') {
    persist(
      { llm_connection: { openai_api_key: openaiApiKey.value.trim() } },
      isUpdatingOpenai,
      openaiApiKey
    );
  } else {
    persist(
      { llm_connection: { anthropic_api_key: anthropicApiKey.value.trim() } },
      isUpdatingAnthropic,
      anthropicApiKey
    );
  }
};

const handleRemove = () => {
  if (!canRemove.value) return;
  if (activeProvider.value === 'openai') {
    persist({ llm_connection: { remove_api_key: true } }, isUpdatingOpenai);
  } else {
    persist(
      { llm_connection: { remove_anthropic_key: true } },
      isUpdatingAnthropic
    );
  }
};

async function handleFeatureToggle({ feature, enabled }) {
  try {
    await captainConfigStore.updatePreferences({
      captain_features: { [feature]: enabled },
    });
    useAlert(t('CAPTAIN_SETTINGS.API.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.API.ERROR'));
    captainConfigStore.fetch();
  }
}

async function handleModelChange({ feature, model }) {
  try {
    await captainConfigStore.updatePreferences({
      captain_models: { [feature]: model },
    });
    useAlert(t('CAPTAIN_SETTINGS.API.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.API.ERROR'));
    captainConfigStore.fetch();
  }
}

const modelFeatures = computed(() => [
  {
    key: 'editor',
    title: t('CAPTAIN_SETTINGS.MODEL_CONFIG.EDITOR.TITLE'),
    description: t('CAPTAIN_SETTINGS.MODEL_CONFIG.EDITOR.DESCRIPTION'),
  },
  {
    key: 'assistant',
    title: t('CAPTAIN_SETTINGS.MODEL_CONFIG.ASSISTANT.TITLE'),
    description: t('CAPTAIN_SETTINGS.MODEL_CONFIG.ASSISTANT.DESCRIPTION'),
  },
  {
    key: 'copilot',
    title: t('CAPTAIN_SETTINGS.MODEL_CONFIG.COPILOT.TITLE'),
    description: t('CAPTAIN_SETTINGS.MODEL_CONFIG.COPILOT.DESCRIPTION'),
  },
]);

const featureToggles = computed(() => [
  {
    key: 'label_suggestion',
    title: t('CAPTAIN_SETTINGS.FEATURES.LABEL_SUGGESTION.TITLE'),
    description: t('CAPTAIN_SETTINGS.FEATURES.LABEL_SUGGESTION.DESCRIPTION'),
  },
  {
    key: 'help_center_search',
    title: t('CAPTAIN_SETTINGS.FEATURES.HELP_CENTER_SEARCH.TITLE'),
    description: t('CAPTAIN_SETTINGS.FEATURES.HELP_CENTER_SEARCH.DESCRIPTION'),
  },
  {
    key: 'audio_transcription',
    title: t('CAPTAIN_SETTINGS.FEATURES.AUDIO_TRANSCRIPTION.TITLE'),
    description: t('CAPTAIN_SETTINGS.FEATURES.AUDIO_TRANSCRIPTION.DESCRIPTION'),
  },
]);

const modelsFor = key => captainConfigStore.getModelsForFeature(key);
// Modelos "em breve" não são selecionáveis — ficam fora do AiSelect.
const modelOptionsFor = key =>
  modelsFor(key)
    .filter(m => !m.coming_soon)
    .map(m => ({ value: m.id, label: m.display_name }));
const selectedModelFor = key =>
  captainConfigStore.getSelectedModelForFeature(key);
const featureEnabled = key => Boolean(features.value?.[key]?.enabled);
const onFeatureToggle = (key, val) =>
  handleFeatureToggle({ feature: key, enabled: val });
const onModelPick = (key, model) => handleModelChange({ feature: key, model });

onMounted(() => {
  if (captainEnabled.value) {
    captainConfigStore.fetch();
  }
});
</script>

<template>
  <div class="px-6 pt-6 pb-20 mx-auto max-w-3xl">
    <header class="mb-7">
      <h1
        class="text-[28px] sm:text-[32px] font-bold tracking-[-0.02em] text-n-slate-12"
      >
        {{ t('CAPTAIN_SETTINGS.TITLE') }}
      </h1>
      <p class="mt-1.5 text-[13.5px] leading-relaxed text-n-slate-11">
        {{ t('CAPTAIN_SETTINGS.INTRO') }}
      </p>
    </header>

    <div v-if="isLoading" class="py-12 text-sm text-center text-n-slate-10">
      {{ t('CAPTAIN_SETTINGS.LOADING') }}
    </div>

    <div
      v-else-if="!captainEnabled"
      class="py-12 text-sm text-center text-n-slate-10"
    >
      {{ t('CAPTAIN_SETTINGS.NOT_ENABLED') }}
    </div>

    <template v-else>
      <!-- Provedor -->
      <section>
        <p :class="SECTION_LABEL">
          {{ t('CAPTAIN_SETTINGS.SECTIONS.PROVIDER') }}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <AiProviderCard
            v-for="p in PROVIDERS"
            :key="p.id"
            :name="p.name"
            :desc="p.desc"
            :color="p.color"
            :icon="p.icon"
            :provider="p.id"
            :selected="activeProvider === p.id"
            :class="p.disabled ? 'opacity-55 pointer-events-none' : ''"
            @select="selectProvider(p)"
          />
        </div>
      </section>

      <!-- Chave de API (destaque) -->
      <section class="mt-7">
        <p :class="SECTION_LABEL">
          {{ t('CAPTAIN_SETTINGS.SECTIONS.API_KEY') }}
        </p>
        <AiCard
          class="shadow-md ring-1 ring-n-brand/20"
          :title="
            t('CAPTAIN_SETTINGS.CONNECTION.KEY_LABEL', { provider: activeName })
          "
          :description="
            t('CAPTAIN_SETTINGS.CONNECTION.DESCRIPTION', {
              provider: activeName,
            })
          "
        >
          <template #leading>
            <span
              class="grid flex-none place-items-center text-white rounded-xl bg-n-brand size-10"
            >
              <span class="i-lucide-key-round size-5" />
            </span>
          </template>
          <template #actions>
            <AiBadge
              :variant="activeConfigured ? 'on' : 'off'"
              :label="
                activeConfigured
                  ? t('CAPTAIN_SETTINGS.CONNECTION.STATUS_CONNECTED')
                  : t('CAPTAIN_SETTINGS.CONNECTION.STATUS_DISCONNECTED')
              "
            >
              <span v-if="activeConfigured" class="i-lucide-check size-3" />
            </AiBadge>
          </template>

          <div class="space-y-3">
            <div
              v-if="activeMasked"
              class="flex gap-3 justify-between items-center px-3 py-2 rounded-xl border border-n-weak bg-n-alpha-1"
            >
              <span
                class="flex gap-1.5 items-center text-[12.5px] font-medium text-n-slate-11"
              >
                <span
                  class="flex-none i-lucide-lock size-3.5 text-n-slate-10"
                />
                {{ t('CAPTAIN_SETTINGS.CONNECTION.CURRENT_KEY') }}
              </span>
              <span
                class="font-mono text-[12.5px] tracking-wide truncate text-n-slate-11"
              >
                {{ activeMasked }}
              </span>
            </div>

            <AiField
              v-model="activeKey"
              secret
              :placeholder="
                t('CAPTAIN_SETTINGS.CONNECTION.PLACEHOLDER', {
                  provider: activeName,
                })
              "
            />

            <div
              class="flex flex-col gap-3 justify-between items-stretch sm:flex-row sm:items-center"
            >
              <p class="flex gap-1.5 items-center text-[12px] text-n-slate-10">
                <span class="flex-none i-lucide-shield-check size-3.5" />
                {{ t('CAPTAIN_SETTINGS.CONNECTION.SECURITY_NOTE') }}
              </p>
              <div class="flex flex-none gap-2 justify-end">
                <AiButton
                  variant="ghost"
                  :disabled="!canRemove"
                  @click="handleRemove"
                >
                  {{ t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.REMOVE') }}
                </AiButton>
                <AiButton :disabled="!canSave" @click="handleSave">
                  <span class="i-lucide-check size-4" />
                  {{
                    activeUpdating
                      ? t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVING')
                      : t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVE')
                  }}
                </AiButton>
              </div>
            </div>
          </div>
        </AiCard>
      </section>

      <!-- Modelos -->
      <section class="mt-7">
        <p :class="SECTION_LABEL">
          {{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.TITLE') }}
        </p>
        <AiListGroup>
          <AiListRow
            v-for="feat in modelFeatures"
            :key="feat.key"
            :title="feat.title"
            :subtitle="feat.description"
          >
            <template #trailing>
              <AiSelect
                class="flex-none w-44"
                :model-value="selectedModelFor(feat.key)"
                :options="modelOptionsFor(feat.key)"
                @update:model-value="model => onModelPick(feat.key, model)"
              />
            </template>
          </AiListRow>
        </AiListGroup>
      </section>

      <!-- Recursos -->
      <section class="mt-7">
        <p :class="SECTION_LABEL">
          {{ t('CAPTAIN_SETTINGS.FEATURES.TITLE') }}
        </p>
        <AiListGroup>
          <AiListRow
            v-for="feat in featureToggles"
            :key="feat.key"
            :title="feat.title"
            :subtitle="feat.description"
          >
            <template #trailing>
              <AiToggle
                :model-value="featureEnabled(feat.key)"
                @update:model-value="val => onFeatureToggle(feat.key, val)"
              />
            </template>
          </AiListRow>
        </AiListGroup>
      </section>
    </template>
  </div>
</template>
