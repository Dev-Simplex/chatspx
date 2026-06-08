<script setup>
// Snackbar inferior reaproveitável para o módulo Kanban (P1-06).
// Renderiza ações reversíveis com botão Desfazer.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { snackbar, dismiss } = useKanbanSnackbar();
const { t } = useI18n();

const variantClass = computed(() => {
  switch (snackbar.value.variant) {
    case 'success':
      return 'bg-iris-700 text-white';
    case 'warning':
      return 'bg-amber-600 text-white';
    case 'error':
      return 'bg-ruby-700 text-white';
    default:
      return 'bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900';
  }
});

const handleAction = async () => {
  const action = snackbar.value.action;
  if (!action?.onClick) return;
  try {
    await action.onClick();
  } finally {
    dismiss();
  }
};
</script>

<template>
  <transition name="snackbar-fade">
    <div
      v-if="snackbar.visible"
      class="fixed left-1/2 -translate-x-1/2 bottom-4 z-50 max-w-[90vw] w-fit"
      role="alert"
      aria-live="polite"
    >
      <div
        class="flex items-center gap-3 px-4 h-12 rounded-xl shadow-lg border border-slate-800/10 dark:border-white/10 text-sm font-medium"
        :class="[variantClass]"
      >
        <span class="truncate max-w-[60vw]">{{ snackbar.message }}</span>

        <button
          v-if="snackbar.action"
          type="button"
          class="ml-1 px-2 h-7 rounded-md bg-white/15 hover:bg-white/25 text-white text-sm font-semibold focus:outline-none focus:ring-2 focus:ring-white/40 transition-colors"
          :aria-label="t('KANBAN.SNACKBAR.UNDO_ARIA')"
          @click="handleAction"
        >
          {{ snackbar.action.label || t('KANBAN.SNACKBAR.UNDO') }}
        </button>

        <button
          type="button"
          class="ml-1 inline-flex items-center justify-center size-6 rounded hover:bg-white/15 text-white/80 transition-colors"
          :aria-label="t('KANBAN.SHORTCUTS.CLOSE')"
          @click="dismiss"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </div>
    </div>
  </transition>
</template>
