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
    isEnabled.value = !!currentAccount.value?.settings?.resolve_assignment_gate;
  },
  { deep: true, immediate: true }
);

const toggle = async () => {
  try {
    await updateAccount({ resolve_assignment_gate: isEnabled.value });
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggle" />
      </div>
    </template>
  </SectionLayout>
</template>
