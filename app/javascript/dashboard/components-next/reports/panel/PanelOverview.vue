<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import { useReportFeatures } from 'dashboard/composables/useReportFeatures';
import CsatReportsAPI from 'dashboard/api/csatReports';
import NpsReportsAPI from 'dashboard/api/npsReports';
import SLAReportsAPI from 'dashboard/api/slaReports';
import {
  formatDuration,
  formatPercent,
  teamDisplayName,
} from 'dashboard/helper/reportFormat';
import PanelKpiCard from './PanelKpiCard.vue';
import PanelShortcutCard from './PanelShortcutCard.vue';
import PanelVolumeChart from './PanelVolumeChart.vue';
import PanelLiveCard from './PanelLiveCard.vue';
import PanelFirstResponseByTeam from './PanelFirstResponseByTeam.vue';
import PanelFunnelCard from './PanelFunnelCard.vue';
import ReportVerdict from 'dashboard/components-next/reports/ui/ReportVerdict.vue';
import ReportDrilldownPanel from 'dashboard/components-next/reports/ReportDrilldownPanel.vue';

// Aba Visao geral do painel de Relatorios: os numeros do periodo, os atalhos para os outros
// relatorios, o volume no tempo, a situacao ao vivo, a 1a resposta por time e o funil.
// Tudo sai dos endpoints que ja alimentam os relatorios detalhados.
const props = defineProps({
  // { since, until, prevSince, prevUntil, hourly, vsKey } em segundos unix
  period: { type: Object, required: true },
  inboxId: { type: Number, default: null },
});

const DEFAULT_GOAL = 300;

const { t } = useI18n();
const store = useStore();
const teams = useMapGetter('teams/getTeams');

const summary = ref(null);
const previous = ref(null);
const { enabled } = useReportFeatures();
const csat = ref(null);
const csatPrevious = ref(null);
const nps = ref(null);
const sla = ref(null);
const bot = ref(null);
const volume = ref({ labels: [], received: [], resolved: [] });
const teamRows = ref([]);
const hasFunnel = ref(true);
const drilldown = ref(null);

const inbox = computed(() => props.inboxId || undefined);

const satisfaction = metrics => {
  if (!metrics?.total_count) return null;
  const happy =
    (metrics.ratings_count?.[4] || 0) + (metrics.ratings_count?.[5] || 0);
  return (happy / metrics.total_count) * 100;
};

// "8 de cada 10" e mais facil de imaginar que "83%". Arredonda para baixo: 95% nao vira "10 de 10".
const outOfTen = pct => (pct >= 100 ? 10 : Math.floor(pct / 10));

const changePct = (current, before) => {
  if (current === null || current === undefined || !before) return null;
  return ((current - before) / before) * 100;
};

const optional = promise => promise.then(({ data }) => data).catch(() => null);

const loadVolume = async () => {
  const { since, until, hourly } = props.period;
  const params = {
    from: since,
    to: until,
    groupBy: hourly ? 'hour' : 'day',
    inboxId: inbox.value,
  };
  const [received, resolved] = await Promise.all([
    ReportsAPI.getReports({ ...params, metric: 'conversations_count' }),
    ReportsAPI.getReports({ ...params, metric: 'resolutions_count' }),
  ]);
  const resolvedBy = Object.fromEntries(
    resolved.data.map(point => [point.timestamp, point.value])
  );
  volume.value = {
    labels: received.data.map(point =>
      format(fromUnixTime(point.timestamp), hourly ? "H'h'" : 'dd/MM')
    ),
    received: received.data.map(point => point.value),
    resolved: received.data.map(point => resolvedBy[point.timestamp] || 0),
  };
};

const loadTeams = async () => {
  const { data } = await SummaryReportsAPI.getTeamReports({
    since: props.period.since,
    until: props.period.until,
    inboxId: inbox.value,
  });
  teamRows.value = data
    .filter(row => row.avg_first_response_time > 0)
    .map(row => ({
      id: row.id,
      name:
        teamDisplayName(teams.value.find(team => team.id === row.id)?.name) ||
        `#${row.id}`,
      seconds: row.avg_first_response_time,
    }));
};

const load = async () => {
  const { since, until, prevSince, prevUntil } = props.period;
  const range = { from: since, to: until, inbox_id: inbox.value };
  try {
    const [current, before] = await Promise.all([
      ReportsAPI.getSummary(
        since,
        until,
        'account',
        undefined,
        undefined,
        false,
        inbox.value
      ),
      ReportsAPI.getSummary(
        prevSince,
        prevUntil,
        'account',
        undefined,
        undefined,
        false,
        inbox.value
      ),
    ]);
    summary.value = current.data;
    previous.value = before.data;
  } catch {
    useAlert(t('REPORTS_PANEL.LOAD_FAILED'));
  }
  [csat.value, csatPrevious.value, nps.value, sla.value, bot.value] =
    await Promise.all([
      optional(CsatReportsAPI.getMetrics(range)),
      optional(
        CsatReportsAPI.getMetrics({ ...range, from: prevSince, to: prevUntil })
      ),
      optional(NpsReportsAPI.getMetrics(range)),
      optional(SLAReportsAPI.getMetrics(range)),
      optional(
        ReportsAPI.getBotSummary({
          from: since,
          to: until,
          inboxId: inbox.value,
        })
      ),
    ]);
  loadVolume().catch(() => {});
  loadTeams().catch(() => {});
};

const goalSeconds = computed(
  () =>
    summary.value?.signals?.find(signal => signal.metric === 'first_response')
      ?.goal || DEFAULT_GOAL
);

const vsLabel = computed(() => t(`REPORTS_PANEL.VS.${props.period.vsKey}`));

const kpis = computed(() => {
  const now = summary.value;
  const before = previous.value;
  if (!now) return [];
  const csatNow = satisfaction(csat.value);
  const list = [
    {
      key: 'conversations_count',
      icon: 'i-lucide-messages-square',
      label: t('REPORTS_PANEL.KPI.CONVERSATIONS'),
      value: now.conversations_count.toLocaleString(),
      caption: t('REPORTS_PANEL.KPI.CONVERSATIONS_SUB'),
      change: changePct(now.conversations_count, before?.conversations_count),
      better: 'neutral',
      clickable: now.conversations_count > 0,
    },
    {
      key: 'avg_first_response_time',
      icon: 'i-lucide-timer',
      label: t('REPORTS_PANEL.KPI.FIRST_RESPONSE'),
      value: now.p50_first_response_time
        ? formatDuration(now.p50_first_response_time, t)
        : t('REPORTS_PANEL.KPI.NO_DATA'),
      caption: now.p50_first_response_time
        ? t('REPORTS_PANEL.KPI.FIRST_RESPONSE_SUB')
        : '',
      change: now.p50_first_response_time
        ? changePct(
            now.p50_first_response_time,
            before?.p50_first_response_time
          )
        : null,
      better: 'lower',
      clickable: now.first_response_count > 0,
    },
    {
      key: 'resolutions_count',
      icon: 'i-lucide-circle-check-big',
      label: t('REPORTS_PANEL.KPI.RESOLVED'),
      value: now.resolutions_count.toLocaleString(),
      caption: t('REPORTS_PANEL.KPI.RESOLVED_SUB'),
      change: changePct(now.resolutions_count, before?.resolutions_count),
      better: 'higher',
      clickable: now.resolutions_count > 0,
    },
  ];
  // Satisfação só entra quando alguma caixa de entrada pede a pesquisa.
  if (enabled.value.csat) {
    list.push({
      key: 'csat',
      icon: 'i-lucide-smile',
      label: t('REPORTS_PANEL.KPI.CSAT'),
      value:
        csatNow === null
          ? t('REPORTS_PANEL.KPI.NO_DATA')
          : t('REPORTS_PANEL.KPI.OUT_OF_TEN', { n: outOfTen(csatNow) }),
      caption:
        csatNow === null
          ? t('REPORTS_PANEL.KPI.CSAT_EMPTY')
          : t('REPORTS_PANEL.KPI.CSAT_SUB', { pct: formatPercent(csatNow) }),
      change: changePct(csatNow, satisfaction(csatPrevious.value)),
      better: 'higher',
      to: { name: 'csat_reports' },
    });
  }
  return list;
});

const shortcuts = computed(() => {
  const list = [];
  if (enabled.value.nps && nps.value) {
    const answered = nps.value.total_count > 0;
    list.push({
      key: 'nps',
      icon: 'i-lucide-heart-handshake',
      label: t('REPORTS_PANEL.SHORTCUT.NPS'),
      value: answered
        ? String(nps.value.nps_score)
        : t('REPORTS_PANEL.KPI.NO_DATA'),
      caption: answered
        ? t('REPORTS_PANEL.SHORTCUT.NPS_SUB', {
            pct: formatPercent(nps.value.promoters_pct),
          })
        : t('REPORTS_PANEL.SHORTCUT.NPS_EMPTY'),
      to: { name: 'nps_reports' },
    });
  }
  if (enabled.value.sla && sla.value) {
    const total = sla.value.total_applied_slas || 0;
    const misses = sla.value.number_of_sla_misses || 0;
    list.push({
      key: 'sla',
      icon: 'i-lucide-alarm-clock-check',
      label: t('REPORTS_PANEL.SHORTCUT.SLA'),
      value: total
        ? t('REPORTS_PANEL.KPI.OUT_OF_TEN', {
            n: outOfTen(parseFloat(sla.value.hit_rate)),
          })
        : t('REPORTS_PANEL.KPI.NO_DATA'),
      caption: total
        ? t(
            'REPORTS_PANEL.SHORTCUT.SLA_SUB',
            { n: misses, pct: formatPercent(parseFloat(sla.value.hit_rate)) },
            misses
          )
        : t('REPORTS_PANEL.SHORTCUT.SLA_EMPTY'),
      to: { name: 'sla_reports' },
    });
  }
  if (bot.value) {
    list.push({
      key: 'bot',
      icon: 'i-lucide-bot',
      label: t('REPORTS_PANEL.SHORTCUT.AI'),
      value: (bot.value.bot_resolutions_count || 0).toLocaleString(),
      caption: t('REPORTS_PANEL.SHORTCUT.AI_SUB'),
      to: { name: 'bot_reports' },
    });
  }
  return list;
});

const verdictSignals = computed(() => [
  ...(summary.value?.signals || []),
  ...(enabled.value.csat ? csat.value?.signals || [] : []),
  // NPS com poucas respostas nao entra no julgamento (a nota ainda nao e confiavel)
  ...(!enabled.value.nps || nps.value?.reliable === false
    ? []
    : nps.value?.signals || []),
  ...(enabled.value.sla ? sla.value?.signals || [] : []),
]);

const hasVolume = computed(() =>
  volume.value.received.some(value => value > 0)
);

const openKpi = kpi => {
  drilldown.value = { key: kpi.key, name: kpi.label };
};

const drilldownFilters = computed(() => ({
  from: props.period.since,
  to: props.period.until,
  type: 'account',
  businessHours: false,
  inboxId: inbox.value,
}));

store.dispatch('teams/get');
watch(() => [props.period, props.inboxId], load, { immediate: true });
// os nomes dos times podem chegar depois do relatorio
watch(teams, () => loadTeams().catch(() => {}));
</script>

<template>
  <div class="flex flex-col gap-4">
    <ReportVerdict v-if="summary" :signals="verdictSignals" />
    <section
      class="grid grid-cols-2 gap-3"
      :class="kpis.length === 3 ? 'lg:grid-cols-3' : 'lg:grid-cols-4'"
    >
      <template v-for="kpi in kpis" :key="kpi.key">
        <router-link v-if="kpi.to" :to="kpi.to" class="flex no-underline">
          <PanelKpiCard
            class="w-full transition-shadow hover:shadow-md"
            :icon="kpi.icon"
            :label="kpi.label"
            :value="kpi.value"
            :caption="kpi.caption"
            :change="kpi.change"
            :better="kpi.better"
            :vs-label="vsLabel"
          />
        </router-link>
        <PanelKpiCard
          v-else
          :icon="kpi.icon"
          :label="kpi.label"
          :value="kpi.value"
          :caption="kpi.caption"
          :change="kpi.change"
          :better="kpi.better"
          :vs-label="vsLabel"
          :clickable="kpi.clickable"
          @open="openKpi(kpi)"
        />
      </template>
    </section>

    <section
      v-if="shortcuts.length"
      class="grid grid-cols-1 gap-3"
      :class="{
        'sm:grid-cols-2': shortcuts.length === 2,
        'sm:grid-cols-3': shortcuts.length === 3,
      }"
    >
      <PanelShortcutCard
        v-for="item in shortcuts"
        :key="item.key"
        :icon="item.icon"
        :label="item.label"
        :value="item.value"
        :caption="item.caption"
        :to="item.to"
      />
    </section>

    <section class="grid grid-cols-1 gap-4 lg:grid-cols-12">
      <div
        class="flex flex-col p-5 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0 lg:col-span-8"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2
              class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
            >
              {{ t('REPORTS_PANEL.VOLUME.TITLE') }}
            </h2>
            <p class="mt-0.5 mb-0 text-sm text-n-slate-11">
              {{
                period.hourly
                  ? t('REPORTS_PANEL.VOLUME.SUB_TODAY')
                  : t('REPORTS_PANEL.VOLUME.SUB_DAYS')
              }}
            </p>
          </div>
          <div
            class="flex items-center gap-4 text-xs font-semibold text-n-slate-11"
          >
            <span class="flex items-center gap-1.5">
              <span class="rounded-full size-2.5 bg-n-violet-9" />
              {{ t('REPORTS_PANEL.VOLUME.RECEIVED') }}
            </span>
            <span class="flex items-center gap-1.5">
              <span class="rounded-full size-2.5 bg-n-teal-9" />
              {{ t('REPORTS_PANEL.VOLUME.RESOLVED') }}
            </span>
          </div>
        </div>
        <PanelVolumeChart
          v-if="hasVolume"
          class="mt-4"
          :labels="volume.labels"
          :received="volume.received"
          :resolved="volume.resolved"
          :received-label="t('REPORTS_PANEL.VOLUME.RECEIVED')"
          :resolved-label="t('REPORTS_PANEL.VOLUME.RESOLVED')"
        />
        <p v-else class="mt-6 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_PANEL.VOLUME.EMPTY') }}
        </p>
      </div>
      <PanelLiveCard
        class="lg:col-span-4"
        :inbox-id="inboxId"
        :goal-seconds="goalSeconds"
      />
    </section>

    <section class="grid grid-cols-1 gap-4 lg:grid-cols-12">
      <PanelFirstResponseByTeam
        :class="hasFunnel ? 'lg:col-span-5' : 'lg:col-span-12'"
        :rows="teamRows"
        :goal-seconds="goalSeconds"
      />
      <PanelFunnelCard
        v-if="hasFunnel"
        class="lg:col-span-7"
        @empty="hasFunnel = false"
      />
    </section>

    <ReportDrilldownPanel
      v-if="drilldown"
      :metric="drilldown"
      :filters="drilldownFilters"
      @close="drilldown = null"
    />
  </div>
</template>
