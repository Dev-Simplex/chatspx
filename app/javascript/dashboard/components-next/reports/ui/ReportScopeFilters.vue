<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import { teamDisplayName } from 'dashboard/helper/reportFormat';
import ReportScopeSelect from './ReportScopeSelect.vue';

// Um botao por recorte (Caixa, Time, Atendente), cada um com a propria lista. Uma opcao por recorte
// (o backend dos relatorios recorta por um id de cada vez); cada opcao mostra quantas conversas
// chegaram no periodo, e quem mais recebeu vem primeiro.
const props = defineProps({
  // quais recortes a tela aceita: 'inbox' | 'team' | 'agent'
  groups: { type: Array, default: () => ['inbox'] },
  // { since, until } em segundos unix, para as contagens
  period: { type: Object, default: () => ({}) },
});

// { inbox: id|null, team: id|null, agent: id|null }
const selection = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();
const store = useStore();

const GROUPS = {
  inbox: {
    icon: 'i-lucide-inbox',
    label: 'INBOX',
    all: 'ALL_INBOXES',
    store: 'inboxes/get',
    api: 'getInboxReports',
    source: useMapGetter('inboxes/getInboxes'),
  },
  team: {
    icon: 'i-lucide-users',
    label: 'TEAM',
    all: 'ALL_TEAMS',
    store: 'teams/get',
    api: 'getTeamReports',
    source: useMapGetter('teams/getTeams'),
  },
  agent: {
    icon: 'i-lucide-user-round',
    label: 'AGENT',
    all: 'ALL_AGENTS',
    store: 'agents/get',
    api: 'getAgentReports',
    source: useMapGetter('agents/getAgents'),
  },
};

const counts = ref({});
watch(
  () => props.period,
  () => {
    counts.value = {};
  },
  { deep: true }
);

const load = async group => {
  store.dispatch(GROUPS[group].store);
  const { since, until } = props.period;
  if (!since || counts.value[group]) return;
  try {
    const { data } = await SummaryReportsAPI[GROUPS[group].api]({
      since,
      until,
    });
    counts.value[group] = Object.fromEntries(
      data.map(row => [row.id, row.conversations_count])
    );
  } catch {
    counts.value[group] = {};
  }
};

const optionsOf = group =>
  (GROUPS[group].source.value || [])
    .map(item => ({
      id: item.id,
      name:
        group === 'team' ? teamDisplayName(item.name) : item.name || item.title,
      count: counts.value[group]?.[item.id] ?? null,
    }))
    .sort((a, b) => (b.count || 0) - (a.count || 0));

const pick = (group, id) => {
  selection.value = { ...selection.value, [group]: id };
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <ReportScopeSelect
      v-for="group in groups"
      :key="group"
      :model-value="selection?.[group] ?? null"
      :icon="GROUPS[group].icon"
      :label="t(`REPORTS_UI.FILTERS.${GROUPS[group].label}`)"
      :all-label="t(`REPORTS_UI.FILTERS.${GROUPS[group].all}`)"
      :options="optionsOf(group)"
      @update:model-value="pick(group, $event)"
      @open="load(group)"
    />
  </div>
</template>
