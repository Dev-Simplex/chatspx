<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

/**
 * O aviso de "voce tem alteracao nao salva".
 *
 * Ele LISTA nominalmente o que se perde. "Voce tem alteracoes nao salvas" sem
 * dizer quais obriga o administrador a voltar e conferir campo a campo — que e
 * a mesma opacidade que estas telas existem para corrigir.
 */
const props = defineProps({
  open: { type: Boolean, default: false },
  changedLabels: { type: Array, default: () => [] },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
const dialogRef = ref(null);

const visibleLabels = computed(() => props.changedLabels.slice(0, 8));
const overflowCount = computed(() =>
  Math.max(0, props.changedLabels.length - visibleLabels.value.length)
);

watch(
  () => props.open,
  isOpen => (isOpen ? dialogRef.value?.open() : dialogRef.value?.close())
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    width="md"
    :title="t('INBOX_WIDGET.UNSAVED_DIALOG.TITLE')"
    :description="t('INBOX_WIDGET.UNSAVED_DIALOG.DESCRIPTION')"
    :cancel-button-label="t('INBOX_WIDGET.UNSAVED_DIALOG.STAY')"
    :confirm-button-label="t('INBOX_WIDGET.UNSAVED_DIALOG.LEAVE')"
    @confirm="emit('confirm')"
    @close="emit('cancel')"
  >
    <ul
      v-if="visibleLabels.length"
      class="flex flex-col gap-1 pl-5 list-disc text-sm text-n-slate-11"
      data-testid="unsaved-changes-list"
    >
      <li v-for="label in visibleLabels" :key="label">{{ label }}</li>
      <li v-if="overflowCount">
        {{
          t('INBOX_WIDGET.UNSAVED_DIALOG.AND_MORE', { count: overflowCount })
        }}
      </li>
    </ul>
  </Dialog>
</template>
