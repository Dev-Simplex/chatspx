<script setup>
import { teamDisplayName } from 'dashboard/helper/reportFormat';
import { computed, onMounted, ref, watch } from 'vue';
import { OVERVIEW_METRICS } from '../constants';
import { useToggle } from '@vueuse/core';

import PanelKpiCard from 'dashboard/components-next/reports/panel/PanelKpiCard.vue';
import ReportLiveDot from 'dashboard/components-next/reports/ui/ReportLiveDot.vue';
import { SECTION_TITLE } from 'dashboard/components-next/reports/ui/styles';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n, I18nT } from 'vue-i18n';
import ReportDrilldownPanel from 'dashboard/components-next/reports/ReportDrilldownPanel.vue';

const props = defineProps({
  inboxId: {
    type: [Number, null],
    default: null,
  },
});

const { t } = useI18n();

const uiFlags = useMapGetter('getOverviewUIFlags');
const agentStatus = useMapGetter('agents/getAgentStatus');
const accountConversationMetric = useMapGetter('getAccountConversationMetric');
const store = useStore();

const accounti18nKey = 'OVERVIEW_REPORTS.ACCOUNT_CONVERSATIONS';
const teams = useMapGetter('teams/getTeams');

const teamMenuList = computed(() => {
  return [
    { label: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.ALL_TEAMS'), value: null },
    ...teams.value.map(team => ({
      label: teamDisplayName(team.name),
      value: team.id,
    })),
  ];
});

// Visao Geral no desenho do Painel: cada numero ao vivo e um cartao com icone, valor e o que ele quer dizer.
const LIVE_PILL =
  'px-2 py-0.5 text-[11px] font-semibold rounded-full bg-n-teal-3 text-n-teal-11';
const METRIC_ICONS = {
  open: 'i-lucide-message-circle',
  unattended: 'i-lucide-message-circle-warning',
  unassigned: 'i-lucide-user-x',
  pending: 'i-lucide-clock',
  online: 'i-lucide-user-check',
  busy: 'i-lucide-headset',
  offline: 'i-lucide-user-minus',
};
const agentStatusCards = computed(() =>
  ['online', 'busy', 'offline'].map(key => ({
    key,
    label: t(`OVERVIEW_REPORTS.AGENT_STATUS.${OVERVIEW_METRICS[key]}`),
    hint: t(`OVERVIEW_REPORTS.AGENT_STATUS.HINT.${OVERVIEW_METRICS[key]}`),
    value: Number(agentStatus.value?.[key] || 0),
  }))
);
// Cada numero com o que ele quer dizer embaixo; o numero abre as conversas (ReportDrilldownPanel ao vivo).
const conversationMetrics = computed(() =>
  Object.keys(accountConversationMetric.value).map(key => ({
    key,
    name: t(`${accounti18nKey}.${OVERVIEW_METRICS[key]}`),
    hint: t(`${accounti18nKey}.HINT.${OVERVIEW_METRICS[key]}`),
    value: accountConversationMetric.value[key],
  }))
);
const metricValue = key => Number(accountConversationMetric.value?.[key] || 0);
const agentValue = key => Number(agentStatus.value?.[key] || 0);

const selectedTeam = ref(null);
const selectedTeamLabel = computed(() => {
  const team =
    teamMenuList.value.find(
      menuItem => menuItem.value === selectedTeam.value
    ) || {};
  return team.label;
});
const drilldown = ref(null);
const openDrilldown = metric => {
  if (!metric.value) return;
  drilldown.value = {
    metric: { key: metric.key, name: metric.name },
    filters: { teamId: selectedTeam.value, inboxId: props.inboxId },
  };
};

const fetchData = () => {
  const params = {};
  if (selectedTeam.value) {
    params.team_id = selectedTeam.value;
  }
  if (props.inboxId) {
    params.inbox_id = props.inboxId;
  }
  store.dispatch('fetchAccountConversationMetric', params);
};

watch(() => props.inboxId, fetchData);

const { startRefetching } = useLiveRefresh(fetchData);
const [showDropdown, toggleDropdown] = useToggle();

const handleAction = ({ value }) => {
  toggleDropdown(false);
  selectedTeam.value = value;
  fetchData();
};

onMounted(() => {
  fetchData();
  startRefetching();
});
</script>

<template>
  <section
    v-if="!uiFlags.isFetchingAccountConversationMetric"
    class="relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] p-5"
  >
    <h3
      class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
    >
      {{ t('OVERVIEW_REPORTS.PLAIN_SUMMARY.TITLE') }}
    </h3>
    <ul
      class="mt-3 flex flex-col gap-3 text-base leading-relaxed text-n-slate-12"
    >
      <li class="flex gap-3">
        <span
          class="i-lucide-message-circle size-5 mt-1 shrink-0 text-n-brand"
        />
        <span class="min-w-0">
          <I18nT keypath="OVERVIEW_REPORTS.PLAIN_SUMMARY.OPEN" tag="span">
            <template #open>
              <strong>{{ metricValue('open') }}</strong>
            </template>
            <template #unattended>
              <strong>{{ metricValue('unattended') }}</strong>
            </template>
            <template #unassigned>
              <strong>{{ metricValue('unassigned') }}</strong>
            </template>
            <template #pending>
              <strong>{{ metricValue('pending') }}</strong>
            </template>
          </I18nT>
        </span>
      </li>
      <li class="flex gap-3">
        <span class="i-lucide-users size-5 mt-1 shrink-0 text-n-brand" />
        <span class="min-w-0">
          <I18nT keypath="OVERVIEW_REPORTS.PLAIN_SUMMARY.AGENTS" tag="span">
            <template #online>
              <strong>{{ agentValue('online') }}</strong>
            </template>
            <template #busy>
              <strong>{{ agentValue('busy') }}</strong>
            </template>
            <template #offline>
              <strong>{{ agentValue('offline') }}</strong>
            </template>
          </I18nT>
        </span>
      </li>
    </ul>
    <p class="mt-4 text-sm text-n-slate-11">
      {{ t('OVERVIEW_REPORTS.PLAIN_SUMMARY.HOW_TO_READ') }}
    </p>
  </section>
  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="flex items-center gap-2" :class="SECTION_TITLE">
        <ReportLiveDot />
        {{ t(`${accounti18nKey}.HEADER`) }}
        <span :class="LIVE_PILL">{{ t('OVERVIEW_REPORTS.LIVE') }}</span>
      </h2>
      <div
        v-if="teams.length"
        v-on-clickaway="() => toggleDropdown(false)"
        class="relative flex items-center z-50"
      >
        <Button
          sm
          slate
          faded
          :label="selectedTeamLabel"
          icon="i-lucide-chevron-down"
          trailing-icon
          @click="toggleDropdown()"
        />
        <DropdownMenu
          v-if="showDropdown"
          :menu-items="teamMenuList"
          class="mt-1 top-full ltr:right-0 rtl:left-0"
          @action="handleAction($event)"
        />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <PanelKpiCard
        v-for="metric in conversationMetrics"
        :key="metric.key"
        :icon="METRIC_ICONS[metric.key]"
        :label="metric.name"
        :value="String(metric.value ?? 0)"
        :caption="metric.hint"
        :clickable="Boolean(metric.value)"
        @open="openDrilldown(metric)"
      />
    </div>
  </section>
  <section class="flex flex-col gap-3">
    <h2 class="flex items-center gap-2" :class="SECTION_TITLE">
      <ReportLiveDot />
      {{ t('OVERVIEW_REPORTS.AGENT_STATUS.HEADER') }}
      <span :class="LIVE_PILL">{{ t('OVERVIEW_REPORTS.LIVE') }}</span>
    </h2>
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <PanelKpiCard
        v-for="status in agentStatusCards"
        :key="status.key"
        :icon="METRIC_ICONS[status.key]"
        :label="status.label"
        :value="String(status.value)"
        :caption="status.hint"
      />
    </div>
  </section>
  <ReportDrilldownPanel
    v-if="drilldown"
    :metric="drilldown.metric"
    :filters="drilldown.filters"
    source="live"
    @close="drilldown = null"
  />
</template>
