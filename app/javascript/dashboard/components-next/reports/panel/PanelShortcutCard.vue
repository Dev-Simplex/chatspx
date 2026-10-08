<script setup>
import { useI18n } from 'vue-i18n';

// Atalho para outro relatorio: o numero principal dele e a seta que leva ate la.
defineProps({
  icon: { type: String, required: true },
  label: { type: String, required: true },
  value: { type: String, required: true },
  caption: { type: String, default: '' },
  to: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <router-link
    :to="to"
    :title="t('REPORTS_PANEL.SHORTCUT.OPEN')"
    class="flex items-center gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 no-underline transition-shadow hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand min-w-0"
  >
    <span
      class="flex items-center justify-center rounded-lg size-10 shrink-0 bg-n-alpha-2 text-n-slate-11"
    >
      <span class="size-5" :class="icon" />
    </span>
    <span class="flex flex-col min-w-0 grow">
      <span class="text-sm text-n-slate-11">{{ label }}</span>
      <span class="text-2xl font-semibold tracking-tight tabular-nums">
        {{ value }}
      </span>
      <span v-if="caption" class="text-xs text-n-slate-10 truncate">
        {{ caption }}
      </span>
    </span>
    <span class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-10" />
  </router-link>
</template>
