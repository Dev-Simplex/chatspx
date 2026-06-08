<script setup>
// Bottom sheet "Mover para..." (P1-10).
// Em mobile: long-press num card abre este sheet, listando as outras etapas.
// Cada item tem touch target >= 56px.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  cardName: { type: String, default: '' },
  stages: { type: Array, default: () => [] }, // [{ id, name, color, count }]
  currentStageId: { type: [Number, null], default: null },
});

const emit = defineEmits(['close', 'select']);
const { t } = useI18n();

const handleSelect = stage => {
  if (stage.id === props.currentStageId) return;
  emit('select', stage);
};
</script>

<template>
  <transition name="sheet-fade">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40"
      role="dialog"
      aria-modal="true"
      @click.self="emit('close')"
    >
      <div
        class="w-full sm:max-w-md bg-white dark:bg-slate-900 rounded-t-2xl sm:rounded-2xl border border-slate-200 dark:border-slate-700 shadow-2xl"
      >
        <div
          class="flex items-start justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-800"
        >
          <div class="flex flex-col gap-1 min-w-0">
            <h3
              class="text-sm font-semibold text-slate-900 dark:text-white truncate"
            >
              {{ t('KANBAN.MOBILE.MOVE_SHEET_TITLE', { name: cardName }) }}
            </h3>
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ t('KANBAN.MOBILE.MOVE_SHEET_HINT') }}
            </p>
          </div>
          <button
            type="button"
            class="inline-flex items-center justify-center size-9 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            :aria-label="t('KANBAN.MOBILE.CLOSE')"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <ul class="max-h-[60vh] overflow-y-auto py-2">
          <li v-for="stage in stages" :key="stage.id">
            <button
              type="button"
              class="w-full flex items-center gap-3 px-4 h-14 text-left text-sm hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="stage.id === currentStageId"
              @click="handleSelect(stage)"
            >
              <span
                class="inline-block size-3 rounded-full flex-shrink-0"
                :style="{ background: stage.color || '#6366f1' }"
                aria-hidden="true"
              />
              <span class="flex-1 truncate text-slate-800 dark:text-slate-100">
                {{ stage.name }}
              </span>
              <span class="text-xs text-slate-500 dark:text-slate-400">
                {{ stage.count || 0 }}
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
  </transition>
</template>
