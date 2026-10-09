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
    class="flex items-center gap-4 p-4 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] text-n-slate-12 no-underline transition-shadow hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand min-w-0"
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
