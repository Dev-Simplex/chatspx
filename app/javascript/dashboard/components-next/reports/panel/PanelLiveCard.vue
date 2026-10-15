<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { formatDuration, teamDisplayName } from 'dashboard/helper/reportFormat';
import LiveReportsAPI from 'dashboard/api/liveReports';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ReportDrilldownPanel from 'dashboard/components-next/reports/ReportDrilldownPanel.vue';

// Situacao de agora: quem espera resposta em cada time (com a maior espera) e quem esta online.
// Nao depende do periodo escolhido; atualiza sozinho a cada minuto.
const props = defineProps({
  inboxId: { type: Number, default: null },
  // meta da 1a resposta em segundos: pinta a maior espera de cada time
  goalSeconds: { type: Number, default: 300 },
});

const REFRESH_MS = 60000;
const MAX_AGENTS = 6;

const { t } = useI18n();
const store = useStore();
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const teamRows = ref([]);
const agentOpen = ref({});
const updatedAt = ref(null);
const drilldown = ref(null);
let timer = null;

const oldestWait = async teamId => {
  const { data } = await LiveReportsAPI.getConversationList({
    metric: 'unattended',
    teamId,
    inboxId: props.inboxId,
  });
  return data.payload?.[0]?.value || 0;
};

const load = async () => {
  const [byTeam, byAgent] = await Promise.all([
    LiveReportsAPI.getGroupedConversations({
      groupBy: 'team_id',
      inboxId: props.inboxId,
    }),
    LiveReportsAPI.getGroupedConversations({
      groupBy: 'assignee_id',
      inboxId: props.inboxId,
    }),
  ]);
  const waiting = byTeam.data.filter(row => row.unattended > 0);
  // Sem time nao tem filtro proprio na lista: ali a maior espera fica de fora.
  const waits = await Promise.all(
    waiting.map(row => (row.team_id ? oldestWait(row.team_id) : null))
  );
  teamRows.value = waiting
    .map((row, index) => ({ ...row, oldest: waits[index] }))
    .sort((a, b) => b.unattended - a.unattended);
  agentOpen.value = Object.fromEntries(
    byAgent.data.map(row => [row.assignee_id, row.open])
  );
  updatedAt.value = new Date();
};

const teamName = id => {
  const name = teams.value.find(team => team.id === id)?.name;
  return name ? teamDisplayName(name) : t('REPORTS_PANEL.LIVE.NO_TEAM');
};

const maxWaiting = computed(() =>
  Math.max(1, ...teamRows.value.map(row => row.unattended))
);

const waitTone = seconds => {
  if (seconds <= props.goalSeconds) return 'bg-n-teal-9';
  if (seconds <= props.goalSeconds * 3) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};

const onlineAgents = computed(() =>
  agents.value
    .filter(agent => agent.availability_status === 'online')
    .map(agent => ({ ...agent, open: agentOpen.value[agent.id] || 0 }))
    .sort((a, b) => b.open - a.open)
);

const maxOpen = computed(() =>
  Math.max(1, ...onlineAgents.value.map(agent => agent.open))
);

const updatedLabel = computed(() =>
  updatedAt.value
    ? t('REPORTS_PANEL.LIVE.UPDATED', {
        time: updatedAt.value.toLocaleTimeString(),
      })
    : ''
);

const openTeam = row => {
  drilldown.value = {
    metric: {
      key: 'unattended',
      name: `${teamName(row.team_id)} · ${t('REPORTS_PANEL.LIVE.WAITING')}`,
    },
    filters: { teamId: row.team_id || undefined, inboxId: props.inboxId },
  };
};

onMounted(() => {
  store.dispatch('teams/get');
  store.dispatch('agents/get');
  load();
  timer = setInterval(load, REFRESH_MS);
});
onBeforeUnmount(() => clearInterval(timer));
watch(() => props.inboxId, load);
</script>

<template>
  <section
    class="flex flex-col p-5 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0"
  >
    <div class="flex items-center justify-between gap-2">
      <h2
        class="flex items-center gap-2 m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
      >
        <span class="relative flex size-2.5">
          <span
            class="absolute inline-flex size-full rounded-full bg-n-teal-9 opacity-60 motion-safe:animate-ping"
          />
          <span
            class="relative inline-flex size-2.5 rounded-full bg-n-teal-9"
          />
        </span>
        {{ t('REPORTS_PANEL.LIVE.TITLE') }}
      </h2>
      <span class="text-xs text-n-slate-10 tabular-nums">{{
        updatedLabel
      }}</span>
    </div>
    <p class="mt-0.5 mb-0 text-sm text-n-slate-11">
      {{ t('REPORTS_PANEL.LIVE.SUB') }}
    </p>

    <ul class="flex flex-col gap-1 p-0 m-0 mt-4 list-none">
      <li v-for="row in teamRows" :key="row.team_id || 'none'">
        <button
          type="button"
          class="flex flex-col w-full gap-1.5 px-2 py-1.5 m-0 -mx-2 text-left rounded-lg text-[length:inherit] hover:bg-n-alpha-1"
          @click="openTeam(row)"
        >
          <span class="flex items-center justify-between w-full gap-2">
            <span class="text-sm font-medium text-n-slate-12 truncate">
              {{ teamName(row.team_id) }}
            </span>
            <span class="flex items-center gap-3 shrink-0">
              <span v-if="row.oldest !== null" class="text-xs text-n-slate-10">
                {{
                  t('REPORTS_PANEL.LIVE.OLDEST', {
                    time: formatDuration(row.oldest, t),
                  })
                }}
              </span>
              <span
                class="text-base font-semibold tabular-nums text-n-slate-12"
              >
                {{ row.unattended }}
              </span>
            </span>
          </span>
          <span class="w-full h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <span
              class="block h-full rounded-full"
              :class="
                row.oldest === null ? 'bg-n-slate-9' : waitTone(row.oldest)
              "
              :style="{ width: `${(row.unattended / maxWaiting) * 100}%` }"
            />
          </span>
        </button>
      </li>
      <li v-if="updatedAt && !teamRows.length" class="text-sm text-n-slate-11">
        {{ t('REPORTS_PANEL.LIVE.NO_QUEUE') }}
      </li>
    </ul>

    <div class="h-px my-4 bg-n-weak" />

    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-semibold text-n-slate-12">
        {{
          t('REPORTS_PANEL.LIVE.ONLINE', {
            online: onlineAgents.length,
            total: agents.length,
          })
        }}
      </span>
      <router-link
        :to="{ name: 'live_in_service' }"
        class="text-sm font-semibold text-n-blue-11 no-underline hover:underline"
      >
        {{ t('REPORTS_PANEL.LIVE.OPEN_QUEUE') }}
      </router-link>
    </div>
    <ul class="flex flex-col gap-2.5 p-0 m-0 mt-3 list-none">
      <li
        v-for="agent in onlineAgents.slice(0, MAX_AGENTS)"
        :key="agent.id"
        class="flex items-center gap-3"
      >
        <Avatar
          :name="agent.name"
          :src="agent.thumbnail"
          :size="28"
          status="online"
          rounded-full
        />
        <span class="text-sm text-n-slate-12 truncate grow">{{
          agent.name
        }}</span>
        <span class="text-xs text-n-slate-10 shrink-0">
          {{
            t('REPORTS_PANEL.LIVE.OPEN_COUNT', { n: agent.open }, agent.open)
          }}
        </span>
        <span
          class="w-12 h-1.5 shrink-0 rounded-full bg-n-alpha-2 overflow-hidden"
        >
          <span
            class="block h-full rounded-full bg-n-violet-9"
            :style="{ width: `${(agent.open / maxOpen) * 100}%` }"
          />
        </span>
      </li>
      <li v-if="!onlineAgents.length" class="text-sm text-n-slate-11">
        {{ t('REPORTS_PANEL.LIVE.NOBODY_ONLINE') }}
      </li>
    </ul>

    <ReportDrilldownPanel
      v-if="drilldown"
      :metric="drilldown.metric"
      :filters="drilldown.filters"
      source="live"
      @close="drilldown = null"
    />
  </section>
</template>
