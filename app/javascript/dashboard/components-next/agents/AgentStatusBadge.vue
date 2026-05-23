<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  active: { type: Boolean, default: false },
});

const { t } = useI18n();
</script>

<template>
  <span class="inline-flex items-center gap-1.5 text-xs font-medium">
    <span
      class="size-2 rounded-full"
      :class="
        active ? 'animate-pulse bg-green-500 dark:bg-green-400' : 'bg-n-slate-8'
      "
    />
    <span
      :class="active ? 'text-green-700 dark:text-green-400' : 'text-n-slate-10'"
    >
      {{ active ? t('AGENTS_PAGE.ACTIVE') : t('AGENTS_PAGE.INACTIVE') }}
    </span>
  </span>
</template>
