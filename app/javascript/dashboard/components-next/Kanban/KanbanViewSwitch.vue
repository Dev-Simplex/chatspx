<script setup>
// Switch segmentado de view (Kanban / Lista / Agenda) — P1-01.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  modelValue: { type: String, default: 'kanban' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const views = computed(() => [
  {
    id: 'kanban',
    label: t('KANBAN.HEADER.VIEW_KANBAN'),
    icon: 'i-lucide-layout-grid',
  },
  { id: 'list', label: t('KANBAN.HEADER.VIEW_LIST'), icon: 'i-lucide-list' },
  {
    id: 'calendar',
    label: t('KANBAN.HEADER.VIEW_CALENDAR'),
    icon: 'i-lucide-calendar',
  },
]);

const select = id => emit('update:modelValue', id);
</script>

<template>
  <div
    class="inline-flex items-center rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-0.5"
    role="tablist"
    :aria-label="t('KANBAN.HEADER.VIEW_KANBAN')"
  >
    <button
      v-for="view in views"
      :key="view.id"
      type="button"
      role="tab"
      :aria-selected="modelValue === view.id"
      class="inline-flex items-center gap-1.5 px-3 h-8 rounded-md text-sm font-medium transition-colors"
      :class="[
        modelValue === view.id
          ? 'bg-iris-50 text-iris-700 dark:bg-iris-900/40 dark:text-iris-200'
          : 'text-slate-600 hover:text-slate-900 dark:text-slate-300 dark:hover:text-white',
      ]"
      @click="select(view.id)"
    >
      <Icon :icon="view.icon" class="size-4" />
      <span class="hidden sm:inline">{{ view.label }}</span>
    </button>
  </div>
</template>
