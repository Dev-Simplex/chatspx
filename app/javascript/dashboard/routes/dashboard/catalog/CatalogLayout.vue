<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Moldura das telas do catálogo. O catálogo saiu de Configurações e virou item do menu lateral,
// então é ela que dá o respiro e a rolagem que o SettingsWrapper dava, mais as abas.
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  backButtonLabel: { type: String, default: '' },
  searchPlaceholder: { type: String, default: '' },
  // O formulário do item é uma tela "de dentro": tem botão de voltar, não tem abas.
  hideTabs: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
  loadingMessage: { type: String, default: '' },
  noRecordsFound: { type: Boolean, default: false },
  noRecordsMessage: { type: String, default: '' },
});

const busca = defineModel('searchQuery', { type: String, default: '' });

const { t } = useI18n();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();

// Atendente só lê a lista: as outras três abas são de administrador (a rota também barra).
const abas = computed(() => {
  const todas = [
    { rota: 'catalog_products_index', label: t('CATALOG_MGMT.TABS.ITEMS') },
    { rota: 'catalog_categories', label: t('CATALOG_MGMT.TABS.CATEGORIES') },
    { rota: 'catalog_fields', label: t('CATALOG_MGMT.TABS.FIELDS') },
    {
      rota: 'catalog_integrations',
      label: t('CATALOG_MGMT.TABS.INTEGRATIONS'),
    },
  ];
  return isAdmin.value ? todas : todas.slice(0, 1);
});

const abaAtiva = computed(() =>
  Math.max(
    abas.value.findIndex(aba => aba.rota === route.name),
    0
  )
);

const trocarAba = aba => {
  if (aba.rota === route.name) return;
  router.push({
    name: aba.rota,
    params: { accountId: route.params.accountId },
  });
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full px-4 pt-6 pb-8 m-0 overflow-auto sm:px-8 bg-n-solid-1"
  >
    <div class="flex items-start w-full max-w-[960px] mx-auto">
      <SettingsLayout
        :is-loading="isLoading"
        :loading-message="loadingMessage"
        :no-records-found="noRecordsFound"
        :no-records-message="noRecordsMessage"
      >
        <template #header>
          <BaseSettingsHeader
            :title="title || $t('CATALOG_MGMT.HEADER')"
            :description="description"
            :back-button-label="backButtonLabel"
          />
          <!-- Em tela estreita as quatro abas não cabem: a faixa rola de lado em vez de cortar
               os rótulos. -->
          <div
            v-if="!hideTabs && abas.length > 1"
            data-testid="catalogo-abas"
            class="max-w-full overflow-x-auto no-scrollbar"
          >
            <TabBar
              :tabs="abas"
              :initial-active-tab="abaAtiva"
              class="!w-max"
              @tab-changed="trocarAba"
            />
          </div>
          <div
            v-if="searchPlaceholder || $slots.count || $slots.actions"
            class="flex flex-wrap items-center justify-between gap-3"
          >
            <Input
              v-if="searchPlaceholder"
              v-model="busca"
              :placeholder="searchPlaceholder"
              class="group w-full sm:w-64 min-w-0 [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8 [&>input]:!rounded-[0.625rem]"
              size="sm"
              type="search"
            >
              <template #prefix>
                <Icon
                  icon="i-lucide-search"
                  class="absolute top-1/2 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand size-3.5 ltr:left-2.5 rtl:right-2.5"
                />
              </template>
            </Input>
            <div
              class="flex items-center gap-3 min-w-0 ltr:ml-auto rtl:mr-auto"
            >
              <slot name="count" />
              <slot name="actions" />
            </div>
          </div>
          <slot name="filters" />
        </template>
        <template #preBody>
          <slot name="preBody" />
        </template>
        <template #body>
          <slot name="body" />
        </template>
      </SettingsLayout>
    </div>
  </div>
</template>
