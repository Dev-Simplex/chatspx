<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useAlert } from 'dashboard/composables';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SectionLayout from '../account/components/SectionLayout.vue';
import ModelSelector from './components/ModelSelector.vue';
import FeatureToggle from './components/FeatureToggle.vue';

const { t } = useI18n();
const { captainEnabled } = useCaptain();

const captainConfigStore = useCaptainConfigStore();
const { uiFlags, llmConnection } = storeToRefs(captainConfigStore);

const isLoading = computed(() => uiFlags.value.isFetching);
const openaiApiKey = ref('');
const isUpdatingConnection = ref(false);

const isOpenAiConfigured = computed(() =>
  Boolean(llmConnection.value?.configured)
);
const maskedApiKey = computed(() => llmConnection.value?.maskedApiKey || null);
const lastUpdatedAt = computed(() => {
  const rawDate = llmConnection.value?.updatedAt;
  if (!rawDate) return null;

  const parsedDate = new Date(rawDate);
  if (Number.isNaN(parsedDate.getTime())) return rawDate;

  return parsedDate.toLocaleString();
});
const canSaveOpenAiKey = computed(
  () => openaiApiKey.value.trim().length > 0 && !isUpdatingConnection.value
);
const canRemoveOpenAiKey = computed(
  () => isOpenAiConfigured.value && !isUpdatingConnection.value
);
const connectionStatusLabel = computed(() =>
  isOpenAiConfigured.value
    ? t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.STATUS_CONFIGURED')
    : t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.STATUS_NOT_CONFIGURED')
);

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
    enterprise: true,
  },
  {
    key: 'copilot',
    title: t('CAPTAIN_SETTINGS.MODEL_CONFIG.COPILOT.TITLE'),
    description: t('CAPTAIN_SETTINGS.MODEL_CONFIG.COPILOT.DESCRIPTION'),
    enterprise: true,
  },
]);

const featureToggles = computed(() => [
  {
    key: 'label_suggestion',
  },
  {
    key: 'help_center_search',
    enterprise: true,
  },
  {
    key: 'audio_transcription',
    enterprise: true,
  },
]);

const shouldShowFeature = feature => {
  if (!feature) return true;
  return true;
};

const isFeatureAccessible = feature => {
  if (!feature) return true;
  return true;
};

async function handleSaveOpenAiKey() {
  if (!canSaveOpenAiKey.value) return;

  isUpdatingConnection.value = true;
  try {
    await captainConfigStore.updatePreferences({
      llm_connection: { openai_api_key: openaiApiKey.value.trim() },
    });
    openaiApiKey.value = '';
    useAlert(t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.SUCCESS'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.ERROR')
    );
  } finally {
    isUpdatingConnection.value = false;
  }
}

async function handleRemoveOpenAiKey() {
  if (!canRemoveOpenAiKey.value) return;

  isUpdatingConnection.value = true;
  try {
    await captainConfigStore.updatePreferences({
      llm_connection: { remove_api_key: true },
    });
    useAlert(t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.SUCCESS'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.ERROR')
    );
  } finally {
    isUpdatingConnection.value = false;
  }
}

async function handleFeatureToggle({ feature, enabled }) {
  try {
    await captainConfigStore.updatePreferences({
      captain_features: { [feature]: enabled },
    });
    useAlert(t('CAPTAIN_SETTINGS.API.SUCCESS'));
  } catch (error) {
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
  } catch (error) {
    useAlert(t('CAPTAIN_SETTINGS.API.ERROR'));
    captainConfigStore.fetch();
  }
}

onMounted(() => {
  captainConfigStore.fetch();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :no-records-message="t('CAPTAIN_SETTINGS.NOT_ENABLED')"
    :loading-message="t('CAPTAIN_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CAPTAIN_SETTINGS.TITLE')"
        :description="t('CAPTAIN_SETTINGS.DESCRIPTION')"
        :link-text="t('CAPTAIN_SETTINGS.LINK_TEXT')"
        icon-name="captain"
        feature-name="captain_billing"
      />
    </template>
    <template #body>
      <div v-if="captainEnabled" class="flex flex-col gap-1">
        <SectionLayout
          :title="t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.TITLE')"
          :description="t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.DESCRIPTION')"
        >
          <div
            data-testid="captain-openai-connection-card"
            class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
          >
            <div class="flex flex-col gap-1">
              <p
                data-testid="captain-openai-status"
                class="text-sm font-medium text-n-slate-12"
              >
                {{ connectionStatusLabel }}
              </p>
              <p v-if="maskedApiKey" class="text-xs text-n-slate-11">
                {{
                  t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.CONFIGURED_KEY', {
                    key: maskedApiKey,
                  })
                }}
              </p>
              <p v-if="lastUpdatedAt" class="text-xs text-n-slate-10">
                {{
                  t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.UPDATED_AT', {
                    date: lastUpdatedAt,
                  })
                }}
              </p>
            </div>

            <div class="mt-4 flex flex-col gap-3 md:flex-row md:items-center">
              <input
                v-model="openaiApiKey"
                data-testid="captain-openai-api-key-input"
                type="password"
                autocomplete="off"
                class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                :placeholder="
                  t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API_KEY_PLACEHOLDER')
                "
              />
              <button
                data-testid="captain-openai-save-key"
                type="button"
                class="inline-flex items-center justify-center rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition hover:brightness-95 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canSaveOpenAiKey"
                @click="handleSaveOpenAiKey"
              >
                {{
                  isUpdatingConnection
                    ? t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVING')
                    : t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVE')
                }}
              </button>
              <button
                data-testid="captain-openai-remove-key"
                type="button"
                class="inline-flex items-center justify-center rounded-lg border border-n-weak bg-transparent px-4 py-2 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canRemoveOpenAiKey"
                @click="handleRemoveOpenAiKey"
              >
                {{ t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.REMOVE') }}
              </button>
            </div>
          </div>
        </SectionLayout>

        <!-- Model Configuration Section -->
        <SectionLayout
          :title="t('CAPTAIN_SETTINGS.MODEL_CONFIG.TITLE')"
          :description="t('CAPTAIN_SETTINGS.MODEL_CONFIG.DESCRIPTION')"
        >
          <div class="grid gap-4">
            <ModelSelector
              v-for="feature in modelFeatures"
              v-show="shouldShowFeature(feature)"
              :key="feature.key"
              :is-allowed="isFeatureAccessible(feature)"
              :feature-key="feature.key"
              :title="feature.title"
              :description="feature.description"
              @change="handleModelChange"
            />
          </div>
        </SectionLayout>

        <!-- Features Section -->
        <SectionLayout
          :title="t('CAPTAIN_SETTINGS.FEATURES.TITLE')"
          :description="t('CAPTAIN_SETTINGS.FEATURES.DESCRIPTION')"
          with-border
        >
          <div class="grid gap-4">
            <FeatureToggle
              v-for="feature in featureToggles"
              v-show="shouldShowFeature(feature)"
              :key="feature.key"
              :is-allowed="isFeatureAccessible(feature)"
              :feature-key="feature.key"
              @change="handleFeatureToggle"
              @model-change="handleModelChange"
            />
          </div>
        </SectionLayout>
      </div>
      <p v-else class="text-sm text-n-slate-11 px-2 py-4">
        {{ t('CAPTAIN_SETTINGS.NOT_ENABLED') }}
      </p>
    </template>
  </SettingsLayout>
</template>
