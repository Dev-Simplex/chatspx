<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { OVERVIEW_METRICS } from '../constants';
import { useToggle } from '@vueuse/core';

import MetricCard from './overview/MetricCard.vue';
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
    ...teams.value.map(team => ({ label: team.name, value: team.id })),
  ];
});

const agentStatusMetrics = computed(() => {
  let metric = {};
  Object.keys(agentStatus.value).forEach(key => {
    const metricName = t(
      `OVERVIEW_REPORTS.AGENT_STATUS.${OVERVIEW_METRICS[key]}`
    );
    metric[metricName] = agentStatus.value[key];
  });
  return metric;
});
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
  <div class="flex flex-col items-center md:flex-row gap-4">
    <div
      class="flex-1 w-full max-w-full md:w-[65%] md:max-w-[65%] conversation-metric"
    >
      <MetricCard
        :header="t(`${accounti18nKey}.HEADER`)"
        :is-loading="uiFlags.isFetchingAccountConversationMetric"
        :loading-message="t(`${accounti18nKey}.LOADING_MESSAGE`)"
      >
        <template v-if="teams.length" #control>
          <div
            v-on-clickaway="() => toggleDropdown(false)"
            class="relative flex items-center group z-50"
          >
            <Button
              sm
              slate
              faded
              :label="selectedTeamLabel"
              icon="i-lucide-chevron-down"
              trailing-icon
              class="capitalize rounded-md group-hover:bg-n-alpha-2"
              @click="toggleDropdown()"
            />
            <DropdownMenu
              v-if="showDropdown"
              :menu-items="teamMenuList"
              class="mt-1 ltr:right-0 rtl:left-0 xl:ltr:right-0 xl:rtl:left-0 top-full"
              label-class="capitalize"
              @action="handleAction($event)"
            />
          </div>
        </template>
        <div
          v-for="metric in conversationMetrics"
          :key="metric.key"
          class="flex-1 min-w-0 pb-2 pr-3"
        >
          <h3 class="text-base text-n-slate-11">
            {{ metric.name }}
          </h3>
          <button
            v-if="metric.value"
            type="button"
            class="p-0 m-0 text-left text-n-slate-12 text-3xl mt-1 tabular-nums underline decoration-dotted decoration-n-slate-8 underline-offset-4 hover:text-n-brand"
            :title="t('REPORT.DRILLDOWN.OPEN')"
            @click="openDrilldown(metric)"
          >
            {{ metric.value }}
          </button>
          <p v-else class="text-n-slate-12 text-3xl mb-0 mt-1">
            {{ metric.value }}
          </p>
          <p class="mt-1 text-xs text-n-slate-10">{{ metric.hint }}</p>
        </div>
      </MetricCard>
    </div>
    <div class="flex-1 w-full max-w-full md:w-[35%] md:max-w-[35%]">
      <MetricCard :header="$t('OVERVIEW_REPORTS.AGENT_STATUS.HEADER')">
        <div
          v-for="(metric, name, index) in agentStatusMetrics"
          :key="index"
          class="flex-1 min-w-0 pb-2"
        >
          <h3 class="text-base text-n-slate-11">
            {{ name }}
          </h3>
          <p class="text-n-slate-12 text-3xl mb-0 mt-1">
            {{ metric }}
          </p>
        </div>
      </MetricCard>
    </div>
  </div>
  <ReportDrilldownPanel
    v-if="drilldown"
    :metric="drilldown.metric"
    :filters="drilldown.filters"
    source="live"
    @close="drilldown = null"
  />
</template>
