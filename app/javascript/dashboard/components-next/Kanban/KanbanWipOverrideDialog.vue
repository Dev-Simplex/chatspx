<script setup>
// KANBAN-P3-08: dialog quando tenta dropar card numa coluna no limite WIP.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  limit: { type: Number, default: 0 },
  over: { type: Number, default: 0 },
});
const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-[1000] flex items-center justify-center bg-black/40 p-4"
      @click.self="emit('cancel')"
    >
      <div
        role="alertdialog"
        aria-modal="true"
        class="w-full max-w-sm rounded-xl bg-white dark:bg-slate-900 shadow-2xl border border-slate-200 dark:border-slate-700 animate-shake"
      >
        <div class="flex items-start gap-3 px-5 py-4">
          <div
            class="flex size-9 items-center justify-center rounded-lg bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300"
          >
            <Icon icon="i-lucide-gauge" class="size-5" />
          </div>
          <div class="flex-1">
            <h3 class="text-base font-semibold text-slate-900 dark:text-white">
              {{ t('KANBAN.WIP.OVER_LIMIT_TOAST') }}
            </h3>
            <p class="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
              {{
                t('KANBAN.WIP.OVER_LIMIT_ARIA', {
                  over: props.over,
                  limit: props.limit,
                })
              }}
            </p>
          </div>
        </div>
        <div
          class="flex items-center justify-end gap-2 border-t border-slate-200 dark:border-slate-800 px-5 py-3"
        >
          <button
            type="button"
            class="rounded-md px-3 py-1.5 text-sm font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800"
            @click="emit('cancel')"
          >
            {{ t('KANBAN.WIP.CANCEL') }}
          </button>
          <button
            type="button"
            class="rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-amber-700"
            @click="emit('confirm')"
          >
            {{ t('KANBAN.WIP.MOVE_ANYWAY') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
