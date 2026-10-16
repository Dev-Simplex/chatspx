<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useReportFeatures } from 'dashboard/composables/useReportFeatures';
import { useGoalsVisibility } from 'dashboard/composables/useGoalsVisibility';

// Todos os Relatorios, em pilula, no cabecalho de cada tela (a Visao Geral vem
// primeiro). A aba acende na tela do assunto e some para quem nao
// tem a permissao ou o recurso da rota (o Rodizio e so de admin) e quando a conta
// nao ligou o que o relatorio mede (CSAT, NPS, SLA).
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { shouldShow } = usePolicy();
const { isReportEnabled } = useReportFeatures();
const { showGoals } = useGoalsVisibility();

const ALL_TABS = [
  { key: 'overview', label: 'OVERVIEW', name: 'account_overview_reports' },
  { key: 'panel', label: 'PANEL', name: 'reports_panel' },
  {
    key: 'conversations',
    label: 'CONVERSATIONS',
    name: 'conversation_reports',
  },
  {
    key: 'agents',
    label: 'AGENTS',
    name: 'agent_reports_index',
    also: ['agent_reports_show'],
  },
  {
    key: 'assignments',
    label: 'ASSIGNMENTS',
    name: 'agent_assignment_reports',
  },
  { key: 'rotation', label: 'ROTATION', name: 'agents_rodizio' },
  {
    key: 'labels',
    label: 'LABELS',
    name: 'label_reports_index',
    also: ['label_reports_show'],
  },
  {
    key: 'inboxes',
    label: 'INBOXES',
    name: 'inbox_reports_index',
    also: ['inbox_reports_show'],
  },
  {
    key: 'teams',
    label: 'TEAMS',
    name: 'team_reports_index',
    also: ['team_reports_show'],
  },
  { key: 'csat', label: 'CSAT', name: 'csat_reports' },
  { key: 'nps', label: 'NPS', name: 'nps_reports' },
  { key: 'sla', label: 'SLA', name: 'sla_reports' },
  { key: 'ai', label: 'AI', name: 'bot_reports' },
  // Metas (CHAT-177) segue a regra de visibilidade da conta, nao so a da rota.
  { key: 'goals', label: 'GOALS', name: 'goals_reports', when: showGoals },
];

const tabs = computed(() =>
  ALL_TABS.filter(tab => {
    if (!isReportEnabled(tab.name)) return false;
    if (tab.when && !tab.when.value) return false;
    const { meta } = router.resolve({ name: tab.name, params: route.params });
    return shouldShow(
      meta.featureFlag,
      meta.permissions,
      meta.installationTypes
    );
  }).map(tab => ({ ...tab, label: t(`REPORTS_PANEL.TABS.${tab.label}`) }))
);

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
