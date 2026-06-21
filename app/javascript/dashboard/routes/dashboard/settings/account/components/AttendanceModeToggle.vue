<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const confirmDialogRef = ref(null);
const pendingMode = ref(null);
const isUpdating = ref(false);

const currentMode = computed(() =>
  currentAccount.value?.settings?.reply_assignment_gate ? 'gated' : 'classic'
);
const MODES = ['classic', 'gated'];

const selectMode = mode => {
  if (mode === currentMode.value || isUpdating.value) return;
  pendingMode.value = mode;
  confirmDialogRef.value.open();
};

const confirmChange = async () => {
  isUpdating.value = true;
  try {
    await updateAccount({
      reply_assignment_gate: pendingMode.value === 'gated',
    });
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.ERROR'));
  } finally {
    isUpdating.value = false;
    confirmDialogRef.value.close();
    pendingMode.value = null;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.NOTE')"
    with-border
  >
    <div class="grid gap-3 sm:grid-cols-2">
      <button
        v-for="mode in MODES"
        :key="mode"
        type="button"
        class="flex flex-col items-start gap-2 rounded-xl border p-4 text-left transition-colors motion-reduce:transition-none"
        :class="
          currentMode === mode
            ? 'border-n-brand ring-1 ring-n-brand bg-n-brand/5'
            : 'border-n-weak hover:border-n-slate-7'
        "
        :aria-pressed="currentMode === mode"
        @click="selectMode(mode)"
      >
        <span class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <span
            :class="
              mode === 'classic'
                ? 'i-lucide-layout-list'
                : 'i-lucide-shield-check'
            "
            class="size-4"
          />
          {{
            t(
              `GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.${mode.toUpperCase()}.TITLE`
            )
          }}
          <span
            v-if="currentMode === mode"
            class="rounded-md bg-n-brand/10 px-1.5 py-0.5 text-xs font-medium text-n-brand"
          >
            {{ t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.ACTIVE') }}
          </span>
        </span>
        <span class="text-body-main text-n-slate-11">
          {{
            t(
              `GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.${mode.toUpperCase()}.DESCRIPTION`
            )
          }}
        </span>
      </button>
    </div>

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      :title="
        t(
          `GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.${(
            pendingMode || 'gated'
          ).toUpperCase()}.TITLE`
        )
      "
      :description="
        t(
          `GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.${(
            pendingMode || 'gated'
          ).toUpperCase()}.DESCRIPTION`
        )
      "
      :confirm-button-label="
        t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.ACTION')
      "
      :is-loading="isUpdating"
      @confirm="confirmChange"
    />
  </SectionLayout>
</template>
