<script setup>
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { computed, onMounted, ref } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import { picoSearch } from '@scmmishra/pico-search';
import { frontendURL } from 'dashboard/helper/URLHelper';
import IntegrationItem from './IntegrationItem.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const getters = useStoreGetters();
const { replaceInstallationName } = useBranding();
const accountId = getters.getCurrentAccountId;

const searchQuery = ref('');
const uiFlags = getters['integrations/getUIFlags'];

const openaiUrl = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/integrations/openai`)
);

const integrationList = computed(
  () => getters['integrations/getAppIntegrations'].value
);

const filteredIntegrationList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return integrationList.value;
  return picoSearch(integrationList.value, query, ['name', 'description']);
});

onMounted(() => {
  store.dispatch('integrations/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('INTEGRATION_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INTEGRATION_SETTINGS.HEADER')"
        :description="
          replaceInstallationName($t('INTEGRATION_SETTINGS.DESCRIPTION'))
        "
        :link-text="$t('INTEGRATION_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('INTEGRATION_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="integrations"
      />
    </template>
    <template #body>
      <div class="flex-grow flex-shrink overflow-auto">
        <router-link
          :to="openaiUrl"
          class="block mb-4 p-4 rounded-xl outline outline-1 outline-n-container bg-n-card hover:bg-n-alpha-2 transition-colors"
        >
          <div class="flex items-center gap-3">
            <div
              class="flex items-center justify-center w-12 h-12 rounded-md border border-n-weak bg-n-alpha-3"
            >
              <span class="text-2xl">{{
                $t('INTEGRATION_SETTINGS.OPENAI.LOGO')
              }}</span>
            </div>
            <div class="flex-1">
              <div class="flex justify-between items-center">
                <span class="text-heading-3 text-n-slate-12">
                  {{ $t('INTEGRATION_SETTINGS.OPENAI.HEADER') }}
                </span>
                <NextButton
                  :label="$t('INTEGRATION_APPS.CONFIGURE')"
                  icon="i-woot-settings"
                  link
                  xs
                />
              </div>
              <p class="text-n-slate-11 text-body-main mt-1">
                {{ $t('INTEGRATION_SETTINGS.OPENAI.DESCRIPTION') }}
              </p>
            </div>
          </div>
        </router-link>

        <span
          v-if="!filteredIntegrationList.length && searchQuery"
          class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
        >
          {{ $t('INTEGRATION_SETTINGS.NO_RESULTS') }}
        </span>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <IntegrationItem
            v-for="item in filteredIntegrationList"
            :id="item.id"
            :key="item.id"
            :logo="item.logo"
            :name="item.name"
            :description="item.description"
            :enabled="item.enabled"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
