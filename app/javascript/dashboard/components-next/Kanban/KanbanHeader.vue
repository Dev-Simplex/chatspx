<script setup>
// Header redesenhado do Kanban (P1-01).
// P2-05: slot opcional `metrics` que exibe métricas do board.
// Eventos:
//   - new-funnel (templates picker)
//   - toggle-filters
//   - toggle-scheduled
//   - shortcuts
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanFunnelSelect from './KanbanFunnelSelect.vue';
import KanbanViewSwitch from './KanbanViewSwitch.vue';

defineProps({
  funnels: { type: Array, default: () => [] },
  funnelId: { type: [Number, String, null], default: null },
  itemCounts: { type: Object, default: () => ({}) },
  viewMode: { type: String, default: 'kanban' },
  hasActiveFilters: { type: Boolean, default: false },
  scheduledCount: { type: Number, default: 0 },
  bulkMode: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:funnelId',
  'update:viewMode',
  'new-funnel',
  'toggle-filters',
  'toggle-scheduled',
  'toggle-bulk',
  'shortcuts',
  'open-automations',
  'open-daily-summary',
]);
const { t } = useI18n();
</script>

<template>
  <header
    class="flex items-center gap-2 flex-wrap px-4 py-3 border-b border-slate-200 dark:border-slate-800 bg-white dark:bg-n-solid-2"
  >
    <KanbanFunnelSelect
      :funnels="funnels"
      :model-value="funnelId"
      :item-counts="itemCounts"
      @update:model-value="v => emit('update:funnelId', v)"
    />

    <KanbanViewSwitch
      :model-value="viewMode"
      class="ml-1"
      @update:model-value="v => emit('update:viewMode', v)"
    />

    <div class="flex-1 min-w-[8px]" />

    <!-- P2-05: slot pra métricas -->
    <slot name="metrics" />

    <div class="flex-1 min-w-[8px]" />

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors relative"
      :aria-label="t('KANBAN.HEADER.FILTERS_TOOLTIP')"
      :title="t('KANBAN.HEADER.FILTERS_TOOLTIP')"
      @click="emit('toggle-filters')"
    >
      <Icon icon="i-lucide-sliders-horizontal" class="size-4" />
      <span class="hidden sm:inline">{{ t('KANBAN.HEADER.FILTERS') }}</span>
      <span
        v-if="hasActiveFilters"
        class="absolute top-1 right-1 size-2 rounded-full bg-iris-500"
        aria-hidden="true"
      />
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
      @click="emit('toggle-scheduled')"
    >
      <Icon icon="i-lucide-calendar-clock" class="size-4" />
      <span class="hidden sm:inline">{{ t('KANBAN.HEADER.SCHEDULED') }}</span>
      <span
        v-if="scheduledCount > 0"
        class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded-full bg-iris-500 text-white text-[10px] font-semibold"
      >
        {{ scheduledCount }}
      </span>
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium transition-colors"
      :class="
        bulkMode
          ? 'bg-iris-600 text-white hover:bg-iris-700'
          : 'text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800'
      "
      :aria-label="t('KANBAN.BULK.TOGGLE')"
      :title="t('KANBAN.BULK.TOGGLE')"
      @click="emit('toggle-bulk')"
    >
      <Icon icon="i-lucide-check-square-2" class="size-4" />
      <span class="hidden lg:inline">{{
        bulkMode ? t('KANBAN.BULK.TOGGLE_OFF') : t('KANBAN.BULK.TOGGLE')
      }}</span>
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-transparent dark:disabled:hover:bg-transparent"
      :disabled="!funnelId"
      :aria-label="t('KANBAN.AUTOMATIONS.NAV_LABEL')"
      :title="
        !funnelId
          ? t('KANBAN.AUTOMATIONS.SELECT_FUNNEL_FIRST')
          : t('KANBAN.AUTOMATIONS.NAV_LABEL')
      "
      @click="emit('open-automations')"
    >
      <Icon icon="i-lucide-zap" class="size-4" />
      <span class="hidden lg:inline">{{
        t('KANBAN.AUTOMATIONS.NAV_LABEL')
      }}</span>
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-transparent dark:disabled:hover:bg-transparent"
      :disabled="!funnelId"
      :aria-label="t('KANBAN.DAILY_SUMMARY.NAV_LABEL')"
      :title="
        !funnelId
          ? t('KANBAN.DAILY_SUMMARY.SELECT_FUNNEL_FIRST')
          : t('KANBAN.DAILY_SUMMARY.NAV_LABEL')
      "
      @click="emit('open-daily-summary')"
    >
      <Icon icon="i-lucide-sun" class="size-4" />
      <span class="hidden lg:inline">{{
        t('KANBAN.DAILY_SUMMARY.NAV_LABEL')
      }}</span>
    </button>

    <button
      type="button"
      class="inline-flex items-center justify-center size-9 rounded-lg text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
      :aria-label="t('KANBAN.HEADER.SHORTCUTS_TOOLTIP')"
      :title="t('KANBAN.HEADER.SHORTCUTS_TOOLTIP')"
      @click="emit('shortcuts')"
    >
      <Icon icon="i-lucide-keyboard" class="size-4" />
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-9 rounded-lg bg-iris-600 text-white text-sm font-medium hover:bg-iris-700 transition-colors"
      :title="t('KANBAN.HEADER.FUNNEL_NEW_TOOLTIP')"
      @click="emit('new-funnel')"
    >
      <Icon icon="i-lucide-plus" class="size-4" />
      <span class="hidden sm:inline">{{ t('KANBAN.HEADER.FUNNEL_NEW') }}</span>
    </button>
  </header>
</template>
