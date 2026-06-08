<script setup>
// Empty state do Kanban (P1-09).
// Variantes:
//   - variant="account" — zero funis na conta
//   - variant="funnel"  — funil sem cards
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  variant: { type: String, default: 'account' }, // 'account' | 'funnel'
});
const emit = defineEmits(['create-blank', 'open-templates', 'open-demo']);
const { t } = useI18n();
</script>

<template>
  <section
    class="flex flex-col items-center justify-center text-center px-4 py-12 sm:py-20 gap-4 max-w-2xl mx-auto"
  >
    <div
      class="size-16 sm:size-20 rounded-full bg-iris-50 dark:bg-iris-900/30 text-iris-600 dark:text-iris-300 flex items-center justify-center"
      aria-hidden="true"
    >
      <Icon icon="i-lucide-layout-grid" class="size-8 sm:size-10" />
    </div>

    <h2
      class="text-xl sm:text-2xl font-semibold text-slate-900 dark:text-white"
    >
      {{
        variant === 'funnel'
          ? t('KANBAN.EMPTY.FUNNEL_TITLE')
          : t('KANBAN.EMPTY.ACCOUNT_TITLE')
      }}
    </h2>

    <p class="text-sm sm:text-base text-slate-600 dark:text-slate-300 max-w-md">
      {{
        variant === 'funnel'
          ? t('KANBAN.EMPTY.FUNNEL_SUBTITLE')
          : t('KANBAN.EMPTY.ACCOUNT_SUBTITLE')
      }}
    </p>

    <div
      v-if="variant === 'account'"
      class="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 mt-3 w-full sm:w-auto"
    >
      <button
        type="button"
        class="inline-flex items-center justify-center gap-2 px-4 h-10 rounded-lg bg-iris-600 text-white text-sm font-medium hover:bg-iris-700 transition-colors w-full sm:w-auto"
        @click="emit('open-templates')"
      >
        <Icon icon="i-lucide-sparkles" class="size-4" />
        {{ t('KANBAN.EMPTY.ACCOUNT_CTA_TEMPLATE') }}
      </button>
      <button
        type="button"
        class="inline-flex items-center justify-center gap-2 px-4 h-10 rounded-lg border border-slate-300 dark:border-slate-700 text-sm font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors w-full sm:w-auto"
        @click="emit('create-blank')"
      >
        <Icon icon="i-lucide-plus" class="size-4" />
        {{ t('KANBAN.EMPTY.ACCOUNT_CTA_BLANK') }}
      </button>
    </div>

    <button
      v-if="variant === 'account'"
      type="button"
      class="text-xs text-slate-500 dark:text-slate-400 hover:text-iris-600 dark:hover:text-iris-300 underline-offset-2 hover:underline mt-1"
      @click="emit('open-demo')"
    >
      {{ t('KANBAN.EMPTY.ACCOUNT_LINK_DEMO') }}
    </button>
  </section>
</template>
