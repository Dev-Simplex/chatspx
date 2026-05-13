<script setup>
import { watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { toast } from 'vue-sonner';
import { usePendingUpdate } from 'dashboard/composables/useAutoUpdate';
import { useReloadGate } from 'dashboard/composables/useReloadGate';
import { reloadWhenSafe } from 'dashboard/helper/autoUpdateHelper';

const TOAST_ID = 'cw-version-update';

const { t } = useI18n();
const pendingUpdate = usePendingUpdate();
const { canReload } = useReloadGate();
const waitingForSafeWindow = ref(false);

const handleReload = () => {
  if (!canReload.value) {
    waitingForSafeWindow.value = true;
    reloadWhenSafe({ onWait: () => {} });
    return;
  }
  reloadWhenSafe();
};

watch(pendingUpdate, isPending => {
  if (!isPending) return;
  toast(t('GENERAL_SETTINGS.VERSION_UPDATE.TITLE'), {
    id: TOAST_ID,
    description: t('GENERAL_SETTINGS.VERSION_UPDATE.DESCRIPTION'),
    duration: Infinity,
    action: {
      label: t('GENERAL_SETTINGS.VERSION_UPDATE.RELOAD'),
      onClick: handleReload,
    },
    cancel: {
      label: t('GENERAL_SETTINGS.VERSION_UPDATE.DISMISS'),
      onClick: () => toast.dismiss(TOAST_ID),
    },
  });
});

watch(canReload, canNow => {
  if (canNow && waitingForSafeWindow.value) {
    waitingForSafeWindow.value = false;
  }
});
</script>

<template>
  <div
    data-testid="version-update-toast"
    class="hidden"
    aria-hidden="true"
    :data-pending-update="pendingUpdate ? 'true' : 'false'"
  >
    <button
      v-if="pendingUpdate"
      type="button"
      data-testid="version-update-reload"
      @click="handleReload"
    >
      {{ t('GENERAL_SETTINGS.VERSION_UPDATE.RELOAD') }}
    </button>
  </div>
</template>
