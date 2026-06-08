<script setup>
// Modal de ajuda com lista de atalhos (P1-12).
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  show: { type: Boolean, default: false },
});
const emit = defineEmits(['close']);
const { t } = useI18n();

const shortcuts = [
  { keys: 'SHORTCUT_N', label: 'NEW_CARD' },
  { keys: 'SHORTCUT_C', label: 'NEW_FUNNEL' },
  { keys: 'SHORTCUT_HELP', label: 'OPEN_HELP' },
  { keys: 'SHORTCUT_ARROWS', label: 'MOVE_FOCUS' },
  { keys: 'SHORTCUT_ESC', label: 'ESC' },
];
</script>

<template>
  <transition name="modal-fade">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="dialog"
      aria-modal="true"
      @click.self="emit('close')"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-700 max-w-md w-full p-6 shadow-2xl"
      >
        <div class="flex items-start justify-between gap-4 mb-4">
          <div class="flex flex-col gap-1">
            <h2 class="text-lg font-semibold text-slate-900 dark:text-white">
              {{ t('KANBAN.SHORTCUTS.TITLE') }}
            </h2>
            <p class="text-sm text-slate-600 dark:text-slate-300">
              {{ t('KANBAN.SHORTCUTS.DESCRIPTION') }}
            </p>
          </div>
          <button
            type="button"
            class="inline-flex items-center justify-center size-8 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors flex-shrink-0"
            :aria-label="t('KANBAN.SHORTCUTS.CLOSE')"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <ul
          class="flex flex-col divide-y divide-slate-100 dark:divide-slate-800"
        >
          <li
            v-for="sc in shortcuts"
            :key="sc.label"
            class="flex items-center justify-between gap-4 py-3"
          >
            <span class="text-sm text-slate-700 dark:text-slate-200">
              {{ t(`KANBAN.SHORTCUTS.${sc.label}`) }}
            </span>
            <kbd
              class="px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-200 text-xs font-mono"
            >
              {{ t(`KANBAN.SHORTCUTS.${sc.keys}`) }}
            </kbd>
          </li>
        </ul>
      </div>
    </div>
  </transition>
</template>
