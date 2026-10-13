<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

// Os assuntos principais dos Relatorios, em pilula, no cabecalho de todas as telas
// (como as abas do prototipo). A aba acende na tela do assunto; as outras telas
// continuam no menu lateral.
const { t } = useI18n();
const route = useRoute();

const tabs = computed(() => [
  {
    key: 'overview',
    label: t('REPORTS_PANEL.TABS.OVERVIEW'),
    name: 'reports_panel',
  },
  {
    key: 'agents',
    label: t('REPORTS_PANEL.TABS.AGENTS'),
    name: 'agent_reports_index',
    also: ['agent_reports_show'],
  },
  { key: 'nps', label: t('REPORTS_PANEL.TABS.NPS'), name: 'nps_reports' },
  { key: 'sla', label: t('REPORTS_PANEL.TABS.SLA'), name: 'sla_reports' },
  { key: 'ai', label: t('REPORTS_PANEL.TABS.AI'), name: 'bot_reports' },
  {
    key: 'inboxes',
    label: t('REPORTS_PANEL.TABS.INBOXES_LABELS'),
    name: 'inbox_reports_index',
    also: ['inbox_reports_show', 'label_reports_index', 'label_reports_show'],
  },
]);

const isActive = tab =>
  route.name === tab.name || (tab.also || []).includes(route.name);
</script>

<template>
  <nav
    class="inline-flex max-w-full gap-0.5 p-1 overflow-x-auto rounded-full border border-n-weak bg-n-alpha-1 no-scrollbar w-fit"
    :aria-label="t('REPORTS_UI.TABS_LABEL')"
  >
    <router-link
      v-for="tab in tabs"
      :key="tab.key"
      :to="{ name: tab.name }"
      :aria-current="isActive(tab) ? 'page' : undefined"
      class="flex items-center h-8 px-3.5 text-[13px] font-semibold rounded-full whitespace-nowrap no-underline"
      :class="
        isActive(tab)
          ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
    >
      {{ tab.label }}
    </router-link>
  </nav>
</template>
