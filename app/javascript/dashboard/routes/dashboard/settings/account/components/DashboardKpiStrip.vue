<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const isEnabled = ref(false);
const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    isEnabled.value =
      !!currentAccount.value?.settings?.show_dashboard_kpi_strip;
  },
  { deep: true, immediate: true }
);

const toggle = async () => {
  try {
    await updateAccount({ show_dashboard_kpi_strip: isEnabled.value });
    useAlert(t('GENERAL_SETTINGS.FORM.KPI_STRIP.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.KPI_STRIP.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.KPI_STRIP.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.KPI_STRIP.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggle" />
      </div>
    </template>
  </SectionLayout>
</template>
