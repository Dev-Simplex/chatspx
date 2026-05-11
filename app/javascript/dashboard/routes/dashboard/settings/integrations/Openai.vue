<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import OpenaiAPI from 'dashboard/api/integrations/openai';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SectionLayout from '../account/components/SectionLayout.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const DEFAULTS = {
  apiKey: '',
  modelDefault: 'gpt-4o-mini',
  modelAdvanced: 'gpt-4o',
};

const apiKey = ref('');
const modelDefault = ref(DEFAULTS.modelDefault);
const modelAdvanced = ref(DEFAULTS.modelAdvanced);
const testStatus = ref(null); // 'idle' | 'testing' | 'ok' | 'fail'
const testMessage = ref('');
const isSaving = ref(false);

const defaultModelOptions = computed(() => [
  { value: 'gpt-4o-mini', label: 'gpt-4o-mini', cost: '$0.15 / $0.60 por 1M' },
  { value: 'gpt-4o', label: 'gpt-4o', cost: '$2.50 / $10 por 1M' },
  { value: 'gpt-4-turbo', label: 'gpt-4-turbo', cost: '$10 / $30 por 1M' },
]);

const advancedModelOptions = computed(() => [
  { value: 'gpt-4o', label: 'gpt-4o', cost: '$2.50 / $10 por 1M' },
  { value: 'gpt-4o-mini', label: 'gpt-4o-mini', cost: '$0.15 / $0.60 por 1M' },
  { value: 'o1-mini', label: 'o1-mini', cost: '$3 / $12 por 1M' },
  { value: 'o1-preview', label: 'o1-preview', cost: '$15 / $60 por 1M' },
]);

watch(
  currentAccount,
  () => {
    const settings = currentAccount.value?.settings || {};
    apiKey.value = settings.openai_api_key || '';
    modelDefault.value = settings.openai_model_default || DEFAULTS.modelDefault;
    modelAdvanced.value =
      settings.openai_model_advanced || DEFAULTS.modelAdvanced;
  },
  { deep: true, immediate: true }
);

const testKey = async () => {
  testStatus.value = 'testing';
  testMessage.value = '';
  try {
    await OpenaiAPI.testKey(apiKey.value);
    testStatus.value = 'ok';
    testMessage.value = t('INTEGRATION_SETTINGS.OPENAI.TEST.SUCCESS');
  } catch (error) {
    testStatus.value = 'fail';
    testMessage.value =
      error?.response?.data?.error ||
      t('INTEGRATION_SETTINGS.OPENAI.TEST.ERROR');
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    await updateAccount({
      openai_api_key: apiKey.value || '',
      openai_model_default: modelDefault.value,
      openai_model_advanced: modelAdvanced.value,
    });
    useAlert(t('INTEGRATION_SETTINGS.OPENAI.SAVE.SUCCESS'));
  } catch {
    useAlert(t('INTEGRATION_SETTINGS.OPENAI.SAVE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const restoreDefaults = () => {
  modelDefault.value = DEFAULTS.modelDefault;
  modelAdvanced.value = DEFAULTS.modelAdvanced;
};

const statusLabel = computed(() => {
  if (testStatus.value === 'testing')
    return t('INTEGRATION_SETTINGS.OPENAI.TEST.RUNNING');
  if (testStatus.value === 'ok') return testMessage.value;
  if (testStatus.value === 'fail') return testMessage.value;
  return '';
});

const statusClass = computed(() => {
  if (testStatus.value === 'ok') return 'text-n-teal-11';
  if (testStatus.value === 'fail') return 'text-n-ruby-11';
  return 'text-n-slate-11';
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('INTEGRATION_SETTINGS.OPENAI.HEADER')"
        :description="t('INTEGRATION_SETTINGS.OPENAI.DESCRIPTION')"
      />
    </template>
    <template #body>
      <div class="flex flex-col w-full max-w-2xl">
        <SectionLayout
          :title="t('INTEGRATION_SETTINGS.OPENAI.API_KEY.TITLE')"
          :description="t('INTEGRATION_SETTINGS.OPENAI.API_KEY.DESCRIPTION')"
          class="!pt-0"
        >
          <div class="flex flex-col gap-3">
            <NextInput
              v-model="apiKey"
              type="password"
              autocomplete="off"
              :placeholder="
                t('INTEGRATION_SETTINGS.OPENAI.API_KEY.PLACEHOLDER')
              "
            />
            <div class="flex gap-2 items-center flex-wrap">
              <NextButton
                :label="t('INTEGRATION_SETTINGS.OPENAI.TEST.BUTTON')"
                variant="outline"
                color="slate"
                :is-loading="testStatus === 'testing'"
                @click="testKey"
              />
              <NextButton
                :label="t('INTEGRATION_SETTINGS.OPENAI.SAVE.BUTTON')"
                variant="solid"
                color="brand"
                :is-loading="isSaving"
                @click="save"
              />
              <span v-if="statusLabel" class="text-sm" :class="statusClass">
                {{ statusLabel }}
              </span>
            </div>
          </div>
        </SectionLayout>

        <SectionLayout
          :title="t('INTEGRATION_SETTINGS.OPENAI.MODEL_DEFAULT.TITLE')"
          :description="
            t('INTEGRATION_SETTINGS.OPENAI.MODEL_DEFAULT.DESCRIPTION')
          "
          with-border
        >
          <div class="flex flex-col gap-2">
            <select
              v-model="modelDefault"
              class="!mb-0 text-sm bg-n-alpha-2 border border-n-weak rounded-md p-2"
            >
              <option
                v-for="opt in defaultModelOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }} — {{ opt.cost }}
              </option>
            </select>
            <p class="text-xs text-n-slate-11">
              {{ t('INTEGRATION_SETTINGS.OPENAI.MODEL_DEFAULT.HELP') }}
            </p>
          </div>
        </SectionLayout>

        <SectionLayout
          :title="t('INTEGRATION_SETTINGS.OPENAI.MODEL_ADVANCED.TITLE')"
          :description="
            t('INTEGRATION_SETTINGS.OPENAI.MODEL_ADVANCED.DESCRIPTION')
          "
          with-border
        >
          <div class="flex flex-col gap-2">
            <select
              v-model="modelAdvanced"
              class="!mb-0 text-sm bg-n-alpha-2 border border-n-weak rounded-md p-2"
            >
              <option
                v-for="opt in advancedModelOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }} — {{ opt.cost }}
              </option>
            </select>
            <p class="text-xs text-n-slate-11">
              {{ t('INTEGRATION_SETTINGS.OPENAI.MODEL_ADVANCED.HELP') }}
            </p>
          </div>
        </SectionLayout>

        <div class="flex gap-2 pt-4">
          <NextButton
            :label="t('INTEGRATION_SETTINGS.OPENAI.RESTORE_DEFAULTS')"
            variant="ghost"
            color="slate"
            @click="restoreDefaults"
          />
          <NextButton
            :label="t('INTEGRATION_SETTINGS.OPENAI.SAVE.BUTTON')"
            variant="solid"
            color="brand"
            :is-loading="isSaving"
            @click="save"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
