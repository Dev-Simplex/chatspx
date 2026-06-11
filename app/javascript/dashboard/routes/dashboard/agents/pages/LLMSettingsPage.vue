<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useAlert } from 'dashboard/composables';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import ModelSelector from 'dashboard/routes/dashboard/settings/captain/components/ModelSelector.vue';
import FeatureToggle from 'dashboard/routes/dashboard/settings/captain/components/FeatureToggle.vue';

const { t } = useI18n();
const { captainEnabled } = useCaptain();

const captainConfigStore = useCaptainConfigStore();
const { uiFlags, llmConnection, anthropicConnection } =
  storeToRefs(captainConfigStore);

const isLoading = computed(() => uiFlags.value.isFetching);

const openaiApiKey = ref('');
const anthropicApiKey = ref('');
const isUpdatingOpenai = ref(false);
const isUpdatingAnthropic = ref(false);

const isOpenAiConfigured = computed(() =>
  Boolean(llmConnection.value?.configured)
);
const maskedOpenaiKey = computed(
  () => llmConnection.value?.maskedApiKey || null
);
const canSaveOpenaiKey = computed(
  () => openaiApiKey.value.trim().length > 0 && !isUpdatingOpenai.value
);
const canRemoveOpenaiKey = computed(
  () => isOpenAiConfigured.value && !isUpdatingOpenai.value
);

const isAnthropicConfigured = computed(() =>
  Boolean(anthropicConnection.value?.configured)
);
const maskedAnthropicKey = computed(
  () => anthropicConnection.value?.maskedApiKey || null
);
const canSaveAnthropicKey = computed(
  () => anthropicApiKey.value.trim().length > 0 && !isUpdatingAnthropic.value
);
const canRemoveAnthropicKey = computed(
  () => isAnthropicConfigured.value && !isUpdatingAnthropic.value
);

async function handleSaveOpenaiKey() {
  if (!canSaveOpenaiKey.value) return;
  isUpdatingOpenai.value = true;
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
    isUpdatingOpenai.value = false;
  }
}

async function handleRemoveOpenaiKey() {
  if (!canRemoveOpenaiKey.value) return;
  isUpdatingOpenai.value = true;
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
    isUpdatingOpenai.value = false;
  }
}

async function handleSaveAnthropicKey() {
  if (!canSaveAnthropicKey.value) return;
  isUpdatingAnthropic.value = true;
  try {
    await captainConfigStore.updatePreferences({
      llm_connection: { anthropic_api_key: anthropicApiKey.value.trim() },
    });
    anthropicApiKey.value = '';
    useAlert(t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.API.SUCCESS'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.API.ERROR')
    );
  } finally {
    isUpdatingAnthropic.value = false;
  }
}

async function handleRemoveAnthropicKey() {
  if (!canRemoveAnthropicKey.value) return;
  isUpdatingAnthropic.value = true;
  try {
    await captainConfigStore.updatePreferences({
      llm_connection: { remove_anthropic_key: true },
    });
    useAlert(t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.API.SUCCESS'));
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.API.ERROR')
    );
  } finally {
    isUpdatingAnthropic.value = false;
  }
}

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
  { key: 'label_suggestion' },
  { key: 'help_center_search', enterprise: true },
  { key: 'audio_transcription', enterprise: true },
]);

onMounted(() => {
  if (captainEnabled.value) {
    captainConfigStore.fetch();
  }
});
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('CAPTAIN_SETTINGS.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_SETTINGS.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="py-12 text-center text-sm text-n-slate-10">
      {{ t('CAPTAIN_SETTINGS.LOADING') }}
    </div>

    <div
      v-else-if="!captainEnabled"
      class="py-12 text-center text-sm text-n-slate-10"
    >
      {{ t('CAPTAIN_SETTINGS.NOT_ENABLED') }}
    </div>

    <template v-else>
      <!-- Provider Cards -->
      <div class="mb-8 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <!-- OpenAI Card -->
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <div class="mb-4 flex items-center justify-between">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.TITLE') }}
            </h3>
            <span
              class="rounded-full px-2.5 py-0.5 text-xs font-medium"
              :class="
                isOpenAiConfigured
                  ? 'bg-g-50 text-g-700 dark:bg-g-900 dark:text-g-200'
                  : 'bg-r-50 text-r-700 dark:bg-r-900 dark:text-r-200'
              "
            >
              {{
                isOpenAiConfigured
                  ? t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.STATUS_CONFIGURED')
                  : t(
                      'CAPTAIN_SETTINGS.OPENAI_CONNECTION.STATUS_NOT_CONFIGURED'
                    )
              }}
            </span>
          </div>

          <p v-if="maskedOpenaiKey" class="mb-3 text-xs text-n-slate-11">
            {{
              t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.CONFIGURED_KEY', {
                key: maskedOpenaiKey,
              })
            }}
          </p>

          <div class="flex flex-col gap-3">
            <input
              v-model="openaiApiKey"
              type="password"
              autocomplete="off"
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
              :placeholder="
                t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.API_KEY_PLACEHOLDER')
              "
            />
            <div class="flex gap-2">
              <button
                type="button"
                class="inline-flex items-center justify-center rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition hover:brightness-95 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canSaveOpenaiKey"
                @click="handleSaveOpenaiKey"
              >
                {{
                  isUpdatingOpenai
                    ? t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVING')
                    : t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.SAVE')
                }}
              </button>
              <button
                type="button"
                class="inline-flex items-center justify-center rounded-lg border border-n-weak bg-transparent px-4 py-2 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canRemoveOpenaiKey"
                @click="handleRemoveOpenaiKey"
              >
                {{ t('CAPTAIN_SETTINGS.OPENAI_CONNECTION.REMOVE') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Anthropic Card -->
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <div class="mb-4 flex items-center justify-between">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.TITLE') }}
            </h3>
            <span
              class="rounded-full px-2.5 py-0.5 text-xs font-medium"
              :class="
                isAnthropicConfigured
                  ? 'bg-g-50 text-g-700 dark:bg-g-900 dark:text-g-200'
                  : 'bg-r-50 text-r-700 dark:bg-r-900 dark:text-r-200'
              "
            >
              {{
                isAnthropicConfigured
                  ? t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.STATUS_CONFIGURED')
                  : t(
                      'CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.STATUS_NOT_CONFIGURED'
                    )
              }}
            </span>
          </div>

          <p v-if="maskedAnthropicKey" class="mb-3 text-xs text-n-slate-11">
            {{
              t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.CONFIGURED_KEY', {
                key: maskedAnthropicKey,
              })
            }}
          </p>

          <div class="flex flex-col gap-3">
            <input
              v-model="anthropicApiKey"
              type="password"
              autocomplete="off"
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
              :placeholder="
                t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.API_KEY_PLACEHOLDER')
              "
            />
            <div class="flex gap-2">
              <button
                type="button"
                class="inline-flex items-center justify-center rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition hover:brightness-95 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canSaveAnthropicKey"
                @click="handleSaveAnthropicKey"
              >
                {{
                  isUpdatingAnthropic
                    ? t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.SAVING')
                    : t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.SAVE')
                }}
              </button>
              <button
                type="button"
                class="inline-flex items-center justify-center rounded-lg border border-n-weak bg-transparent px-4 py-2 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60"
                :disabled="!canRemoveAnthropicKey"
                @click="handleRemoveAnthropicKey"
              >
                {{ t('CAPTAIN_SETTINGS.ANTHROPIC_CONNECTION.REMOVE') }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Model Selectors -->
      <div class="mb-8">
        <h2 class="mb-1 text-base font-semibold text-n-slate-12">
          {{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.TITLE') }}
        </h2>
        <p class="mb-4 text-sm text-n-slate-10">
          {{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.DESCRIPTION') }}
        </p>
        <div class="grid gap-4">
          <ModelSelector
            v-for="feat in modelFeatures"
            :key="feat.key"
            is-allowed
            :feature-key="feat.key"
            :title="feat.title"
            :description="feat.description"
            @change="handleModelChange"
          />
        </div>
      </div>

      <!-- Feature Toggles -->
      <div>
        <h2 class="mb-1 text-base font-semibold text-n-slate-12">
          {{ t('CAPTAIN_SETTINGS.FEATURES.TITLE') }}
        </h2>
        <p class="mb-4 text-sm text-n-slate-10">
          {{ t('CAPTAIN_SETTINGS.FEATURES.DESCRIPTION') }}
        </p>
        <div class="grid gap-4">
          <FeatureToggle
            v-for="feat in featureToggles"
            :key="feat.key"
            is-allowed
            :feature-key="feat.key"
            @change="handleFeatureToggle"
            @model-change="handleModelChange"
          />
        </div>
      </div>
    </template>
  </div>
</template>
