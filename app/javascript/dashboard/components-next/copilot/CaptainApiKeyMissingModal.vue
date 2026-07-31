<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  isAdmin: {
    type: Boolean,
    default: false,
  },
  accountId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const router = useRouter();
const dialogRef = ref(null);

const description = computed(() =>
  props.isAdmin
    ? t('CAPTAIN.COPILOT.API_KEY_MISSING.DESCRIPTION_ADMIN')
    : t('CAPTAIN.COPILOT.API_KEY_MISSING.DESCRIPTION_AGENT')
);

const confirmButtonLabel = computed(() =>
  props.isAdmin
    ? t('CAPTAIN.COPILOT.API_KEY_MISSING.CONFIGURE_BUTTON')
    : t('CAPTAIN.COPILOT.API_KEY_MISSING.OK_BUTTON')
);

const handleClose = () => {
  emit('close');
};

const handleConfirm = () => {
  if (props.isAdmin && props.accountId) {
    router.push({
      name: 'agents_settings',
      params: { accountId: props.accountId },
    });
  }

  dialogRef.value?.close();
};

const open = () => {
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

defineExpose({
  open,
  close,
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CAPTAIN.COPILOT.API_KEY_MISSING.TITLE')"
    :description="description"
    :confirm-button-label="confirmButtonLabel"
    :show-cancel-button="isAdmin"
    :cancel-button-label="t('CAPTAIN.COPILOT.API_KEY_MISSING.CLOSE_BUTTON')"
    @confirm="handleConfirm"
    @close="handleClose"
  />
</template>
