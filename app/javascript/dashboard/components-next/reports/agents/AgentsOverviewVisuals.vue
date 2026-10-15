<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';
import {
  formatDuration,
  formatPercent,
  teamDisplayName,
} from 'dashboard/helper/reportFormat';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ReportCard from 'dashboard/components-next/reports/ui/ReportCard.vue';
import CsatByAgentCard from 'dashboard/components-next/reports/csat/CsatByAgentCard.vue';
import ReportBarList from 'dashboard/components-next/reports/ui/ReportBarList.vue';

// Topo da tela de Agentes no desenho do painel: CSAT por agente, ranking, 1a resposta por agente
// e o rodizio de cada time. As linhas de agente vem do mesmo store da tabela logo abaixo.
const props = defineProps({
  // { from, to, inboxId } em segundos unix, os mesmos filtros da tela
  filters: { type: Object, required: true },
});

const FRT_GOAL = 300;
const MAX_RANK = 6;
const MEDALS = ['bg-n-amber-9', 'bg-n-slate-9', 'bg-n-ruby-9'];

const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');
const summaryRows = useMapGetter('summaryReports/getAgentSummaryReports');

const csatRows = ref([]);
const rotation = ref([]);

const teamMax = team => Math.max(1, ...team.rows.map(row => row.recebidos));

const agentById = id => agents.value.find(agent => agent.id === id) || {};
const shortName = name => {
  const [first, last] = (name || '').split(' ');
  return last ? `${first} ${last[0]}.` : first || '';
};

const tone = (good, near) => {
  if (good) return 'bg-n-teal-9';
  return near ? 'bg-n-amber-9' : 'bg-n-ruby-9';
};

// O rodizio guarda o periodo em datas (de/ate), nao em segundos.
const loadRotation = async () => {
  const day = seconds => format(fromUnixTime(seconds), 'yyyy-MM-dd');
  const period = { de: day(props.filters.from), ate: day(props.filters.to) };
  const { data } = await DistribuicaoDashboardAPI.show(period);
  const teams = await Promise.all(
    (data.times || []).map(async team => {
      const res = await DistribuicaoDashboardAPI.show({
        ...period,
        team_id: team.id,
      });
      return {
        ...team,
        rows: res.data.linhas,
        total: res.data.totais.recebidos,
      };
    })
  );
  rotation.value = teams.filter(team => team.total > 0);
};

watch(
  () => props.filters,
  value => {
    if (!value.from) return;
    // so administrador ve o rodizio: para os outros a chamada e recusada e o cartao some
    loadRotation().catch(() => {
      rotation.value = [];
    });
  },
  { immediate: true, deep: true }
);

const csatByAgent = computed(() =>
  Object.fromEntries(csatRows.value.map(row => [row.id, row.value]))
);

const ranking = computed(() =>
  (summaryRows.value || [])
    .filter(row => row.resolvedConversationsCount > 0)
    .sort((a, b) => b.resolvedConversationsCount - a.resolvedConversationsCount)
    .slice(0, MAX_RANK)
    .map(row => ({ ...row, agent: agentById(row.id) }))
);

const frtBars = computed(() =>
  (summaryRows.value || [])
    .filter(row => row.avgFirstResponseTime > 0)
    .sort((a, b) => a.avgFirstResponseTime - b.avgFirstResponseTime)
    .map(row => ({
      key: row.id,
      label: shortName(agentById(row.id).name),
      hint: agentById(row.id).name,
      value: row.avgFirstResponseTime,
      display: formatDuration(row.avgFirstResponseTime, t),
      barClass: tone(
        row.avgFirstResponseTime <= FRT_GOAL,
        row.avgFirstResponseTime <= FRT_GOAL * 3
      ),
    }))
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="grid grid-cols-1 gap-4 lg:grid-cols-2 xl:grid-cols-3">
      <CsatByAgentCard :filters="filters" @loaded="csatRows = $event" />

      <ReportCard
        :title="t('REPORTS_UI.AGENTS.RANKING_TITLE')"
        :subtitle="t('REPORTS_UI.AGENTS.RANKING_SUB')"
      >
        <p v-if="!ranking.length" class="mt-4 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_UI.AGENTS.RANKING_EMPTY') }}
        </p>
        <ol v-else class="flex flex-col gap-1 p-0 m-0 mt-4 list-none">
          <li
            v-for="(row, index) in ranking"
            :key="row.id"
            class="flex items-center gap-3 py-1.5"
          >
            <span
              class="w-6 text-xs font-bold text-center text-n-slate-10 shrink-0"
            >
              {{ index < 3 ? '' : `${index + 1}º` }}
            </span>
            <span class="relative shrink-0">
              <Avatar
                :name="row.agent.name"
                :src="row.agent.thumbnail"
                :size="36"
                rounded-full
              />
              <span
                v-if="index < 3"
                class="absolute -right-1 -bottom-1 grid place-items-center size-[18px] rounded-full border-2 border-n-solid-2 text-[10px] font-extrabold text-white"
                :class="MEDALS[index]"
              >
                {{ index + 1 }}
              </span>
            </span>
            <span class="flex flex-col min-w-0 grow">
              <span class="text-sm font-bold text-n-slate-12 truncate">
                {{ row.agent.name }}
              </span>
              <span class="text-xs text-n-slate-11 truncate">
                {{
                  t(
                    'REPORTS_UI.AGENTS.RANK_SUB',
                    { n: row.conversationsCount },
                    row.conversationsCount
                  )
                }}
                <template v-if="csatByAgent[row.id] !== undefined">
                  ·
                  {{
                    t('REPORTS_UI.AGENTS.RANK_CSAT', {
                      pct: formatPercent(csatByAgent[row.id]),
                    })
                  }}
                </template>
              </span>
            </span>
            <span class="flex flex-col items-end shrink-0">
              <span
                class="text-base font-extrabold tabular-nums text-n-slate-12"
              >
                {{ row.resolvedConversationsCount }}
              </span>
              <span class="text-[11px] text-n-slate-10">
                {{ t('REPORTS_UI.AGENTS.RESOLVED') }}
              </span>
            </span>
          </li>
        </ol>
      </ReportCard>

      <ReportCard
        :title="t('REPORTS_UI.AGENTS.FRT_TITLE')"
        :subtitle="t('REPORTS_UI.AGENTS.FRT_SUB')"
      >
        <ReportBarList
          :rows="frtBars"
          :goal="FRT_GOAL"
          :max="Math.max(FRT_GOAL * 2, ...frtBars.map(row => row.value))"
          :empty-text="t('REPORTS_UI.AGENTS.FRT_EMPTY')"
        />
        <p v-if="frtBars.length" class="mt-3 mb-0 text-xs text-n-slate-10">
          {{
            t('REPORTS_UI.AGENTS.FRT_GOAL', {
              goal: formatDuration(FRT_GOAL, t),
            })
          }}
        </p>
      </ReportCard>
    </div>

    <ReportCard
      v-if="rotation.length"
      :title="t('REPORTS_UI.ROTATION.TITLE')"
      :subtitle="t('REPORTS_UI.ROTATION.SUB')"
    >
      <template #actions>
        <router-link
          :to="{ name: 'agents_rodizio' }"
          class="flex items-center gap-1.5 text-sm font-bold no-underline text-n-slate-12 hover:text-n-brand"
        >
          <span class="i-lucide-shuffle size-4" />
          {{ t('REPORTS_UI.ROTATION.ADJUST') }}
        </router-link>
      </template>
      <div class="grid grid-cols-1 gap-3 mt-4 md:grid-cols-2">
        <div
          v-for="team in rotation"
          :key="team.id"
          class="p-4 rounded-[18px] border border-n-weak"
        >
          <div class="flex items-center gap-2">
            <span class="rounded-full size-2.5 bg-n-violet-9" />
            <span class="text-sm font-bold text-n-slate-12">
              {{ teamDisplayName(team.name) }}
            </span>
          </div>
          <p class="mt-0.5 mb-0 text-xs text-n-slate-11">
            {{
              t(
                'REPORTS_UI.ROTATION.DISTRIBUTED',
                { n: team.total },
                team.total
              )
            }}
          </p>
          <ul class="flex flex-col gap-2.5 p-0 m-0 mt-3 list-none">
            <li
              v-for="row in team.rows"
              :key="row.user_id"
              class="grid items-center grid-cols-[minmax(0,10rem)_1fr_2rem] gap-3"
            >
              <span class="flex items-center min-w-0 gap-2">
                <Avatar
                  :name="row.nome"
                  :src="agentById(row.user_id).thumbnail"
                  :size="24"
                  rounded-full
                />
                <span
                  class="text-[13px] font-semibold text-n-slate-12 truncate"
                >
                  {{ row.nome }}
                </span>
              </span>
              <span class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
                <span
                  class="block h-full rounded-full bg-n-violet-9"
                  :style="{
                    width: `${(row.recebidos / teamMax(team)) * 100}%`,
                  }"
                />
              </span>
              <span
                class="text-[13px] font-bold text-right tabular-nums text-n-slate-12"
              >
                {{ row.recebidos }}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </ReportCard>
  </div>
</template>
