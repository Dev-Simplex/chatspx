<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { formatDuration, formatPercent } from 'dashboard/helper/reportFormat';
import ReportCard from 'dashboard/components-next/reports/ui/ReportCard.vue';
import ReportBarList from 'dashboard/components-next/reports/ui/ReportBarList.vue';

// Topo das telas de Caixas, Etiquetas e Times no desenho do painel. Usa as MESMAS linhas da
// tabela logo abaixo (store de summaryReports), entao os numeros batem com ela.
const props = defineProps({
  // 'inbox' | 'label' | 'team'
  type: { type: String, required: true },
});

const FRT_GOAL = 300;

const { t } = useI18n();
const inboxRows = useMapGetter('summaryReports/getInboxSummaryReports');
const labelRows = useMapGetter('summaryReports/getLabelSummaryReports');
const teamRows = useMapGetter('summaryReports/getTeamSummaryReports');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getTeams');

const CHANNELS = {
  whatsapp: {
    key: 'WHATSAPP',
    icon: 'i-lucide-message-circle',
    bar: 'bg-n-teal-9',
  },
  instagram: {
    key: 'INSTAGRAM',
    icon: 'i-lucide-instagram',
    bar: 'bg-n-violet-9',
  },
  facebook: { key: 'FACEBOOK', icon: 'i-lucide-facebook', bar: 'bg-n-ruby-9' },
  site: { key: 'SITE', icon: 'i-lucide-globe', bar: 'bg-n-amber-9' },
  email: { key: 'EMAIL', icon: 'i-lucide-mail', bar: 'bg-n-slate-9' },
  telegram: { key: 'TELEGRAM', icon: 'i-lucide-send', bar: 'bg-n-violet-9' },
  api: { key: 'API', icon: 'i-lucide-webhook', bar: 'bg-n-slate-9' },
  other: { key: 'OTHER', icon: 'i-lucide-inbox', bar: 'bg-n-slate-9' },
};

// O WhatsApp do SPX (WAHA) chega como canal de API com sessao: conta como WhatsApp.
const channelOf = inbox => {
  if (!inbox) return 'other';
  if (inbox.waha_session_name) return 'whatsapp';
  return (
    {
      'Channel::Whatsapp': 'whatsapp',
      'Channel::Instagram': 'instagram',
      'Channel::FacebookPage': 'facebook',
      'Channel::WebWidget': 'site',
      'Channel::Email': 'email',
      'Channel::Telegram': 'telegram',
      'Channel::Api': 'api',
    }[inbox.channel_type] || 'other'
  );
};

const frtTone = seconds => {
  if (seconds <= FRT_GOAL) return 'bg-n-teal-9';
  return seconds <= FRT_GOAL * 3 ? 'bg-n-amber-9' : 'bg-n-ruby-9';
};

const rows = computed(
  () =>
    ({ inbox: inboxRows, label: labelRows, team: teamRows })[props.type]
      .value || []
);
const active = computed(() =>
  rows.value
    .filter(row => row.conversationsCount > 0)
    .sort((a, b) => b.conversationsCount - a.conversationsCount)
);
const totalConversations = computed(() =>
  active.value.reduce((sum, row) => sum + row.conversationsCount, 0)
);

const entity = id =>
  ({ inbox: inboxes, label: labels, team: teams })[props.type].value.find(
    item => item.id === id
  ) || {};
const nameOf = row =>
  row.name || entity(row.id).name || entity(row.id).title || `#${row.id}`;

// Caixas: a barra de canais (WhatsApp x Instagram x Site...) e uma linha por caixa.
const channelSplit = computed(() => {
  const totals = {};
  active.value.forEach(row => {
    const channel = channelOf(entity(row.id));
    totals[channel] = (totals[channel] || 0) + row.conversationsCount;
  });
  return Object.entries(totals)
    .sort((a, b) => b[1] - a[1])
    .map(([channel, count]) => ({
      channel,
      count,
      pct: (count / Math.max(1, totalConversations.value)) * 100,
    }));
});

const inboxList = computed(() => {
  const most = Math.max(1, ...active.value.map(row => row.conversationsCount));
  return active.value.map(row => {
    const inbox = entity(row.id);
    const channel = CHANNELS[channelOf(inbox)];
    return {
      id: row.id,
      name: nameOf(row),
      sub: inbox.phone_number || inbox.website_url || inbox.email || '',
      icon: channel.icon,
      bar: channel.bar,
      count: row.conversationsCount,
      width: (row.conversationsCount / most) * 100,
      share: formatPercent(
        (row.conversationsCount / Math.max(1, totalConversations.value)) * 100
      ),
    };
  });
});

// Etiquetas: ranking com a cor de cada etiqueta.
const labelList = computed(() => {
  const most = Math.max(1, ...active.value.map(row => row.conversationsCount));
  return active.value.map(row => ({
    id: row.id,
    name: nameOf(row),
    color: entity(row.id).color,
    count: row.conversationsCount,
    width: (row.conversationsCount / most) * 100,
  }));
});

const frtBars = computed(() =>
  active.value
    .filter(row => row.avgFirstResponseTime > 0)
    .sort((a, b) => a.avgFirstResponseTime - b.avgFirstResponseTime)
    .map(row => ({
      key: row.id,
      label: nameOf(row),
      value: row.avgFirstResponseTime,
      display: formatDuration(row.avgFirstResponseTime, t),
      barClass: frtTone(row.avgFirstResponseTime),
    }))
);

const resolutionBars = computed(() =>
  active.value
    .filter(row => row.avgResolutionTime > 0)
    .sort((a, b) => a.avgResolutionTime - b.avgResolutionTime)
    .map(row => ({
      key: row.id,
      label: nameOf(row),
      value: row.avgResolutionTime,
      display: formatDuration(row.avgResolutionTime, t),
      barClass: 'bg-n-violet-9',
    }))
);

const teamVolume = computed(() =>
  active.value.map(row => ({
    key: row.id,
    label: nameOf(row),
    hint: t('REPORTS_UI.TEAMS.RESOLVED_OF', {
      resolved: row.resolvedConversationsCount || 0,
      total: row.conversationsCount,
    }),
    value: row.conversationsCount,
    display: String(row.conversationsCount),
    barClass: 'bg-n-violet-9',
  }))
);

const frtMax = computed(() =>
  Math.max(FRT_GOAL * 2, ...frtBars.value.map(row => row.value))
);
</script>

<template>
  <div class="grid grid-cols-1 gap-4 lg:grid-cols-12">
    <!-- Caixas -->
    <template v-if="type === 'inbox'">
      <ReportCard
        class="lg:col-span-7"
        :title="t('REPORTS_UI.INBOXES.TITLE')"
        :subtitle="t('REPORTS_UI.INBOXES.SUB')"
      >
        <p v-if="!active.length" class="mt-4 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_UI.INBOXES.EMPTY') }}
        </p>
        <template v-else>
          <div
            class="flex h-3 gap-0.5 mt-4 overflow-hidden rounded-full bg-n-alpha-2"
          >
            <span
              v-for="item in channelSplit"
              :key="item.channel"
              class="block h-full first:rounded-l-full last:rounded-r-full"
              :class="CHANNELS[item.channel].bar"
              :style="{ width: `${item.pct}%` }"
            />
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2.5">
            <span
              v-for="item in channelSplit"
              :key="item.channel"
              class="flex items-center gap-1.5 text-xs font-semibold text-n-slate-11"
            >
              <span
                class="rounded-full size-2"
                :class="CHANNELS[item.channel].bar"
              />
              {{ t(`REPORTS_UI.CHANNELS.${CHANNELS[item.channel].key}`) }}
              <span class="font-extrabold text-n-slate-12">
                {{ formatPercent(item.pct) }}
              </span>
            </span>
          </div>
          <ul class="flex flex-col p-0 m-0 mt-3 list-none">
            <li
              v-for="row in inboxList"
              :key="row.id"
              class="grid items-center grid-cols-[minmax(0,14rem)_1fr_2.5rem_3rem] gap-3 py-2 border-b border-n-weak last:border-b-0"
            >
              <span class="flex items-center min-w-0 gap-3">
                <span
                  class="grid rounded-[10px] size-8 shrink-0 place-items-center bg-n-alpha-2 text-n-slate-11"
                >
                  <span class="size-4" :class="row.icon" />
                </span>
                <span class="flex flex-col min-w-0">
                  <span class="text-sm font-bold text-n-slate-12 truncate">
                    {{ row.name }}
                  </span>
                  <span v-if="row.sub" class="text-xs text-n-slate-10 truncate">
                    {{ row.sub }}
                  </span>
                </span>
              </span>
              <span class="h-1.5 overflow-hidden rounded-full bg-n-alpha-2">
                <span
                  class="block h-full rounded-full"
                  :class="row.bar"
                  :style="{ width: `${row.width}%` }"
                />
              </span>
              <span
                class="text-base font-extrabold text-right tabular-nums text-n-slate-12"
              >
                {{ row.count }}
              </span>
              <span class="text-xs text-right tabular-nums text-n-slate-10">
                {{ row.share }}
              </span>
            </li>
          </ul>
        </template>
      </ReportCard>
      <ReportCard
        class="lg:col-span-5"
        :title="t('REPORTS_UI.INBOXES.FRT_TITLE')"
        :subtitle="t('REPORTS_UI.INBOXES.FRT_SUB')"
      >
        <ReportBarList
          :rows="frtBars"
          :goal="FRT_GOAL"
          :max="frtMax"
          :empty-text="t('REPORTS_UI.INBOXES.EMPTY')"
        />
      </ReportCard>
    </template>

    <!-- Etiquetas -->
    <template v-else-if="type === 'label'">
      <ReportCard
        class="lg:col-span-7"
        :title="t('REPORTS_UI.LABELS.TITLE')"
        :subtitle="t('REPORTS_UI.LABELS.SUB')"
      >
        <p v-if="!active.length" class="mt-4 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_UI.LABELS.EMPTY') }}
        </p>
        <ol v-else class="flex flex-col gap-1 p-0 m-0 mt-3 list-none">
          <li
            v-for="(row, index) in labelList"
            :key="row.id"
            class="grid items-center grid-cols-[1.5rem_minmax(0,12rem)_1fr_2.5rem] gap-3 py-1.5"
          >
            <span class="text-xs font-bold text-n-slate-10 tabular-nums">
              {{ index + 1 }}
            </span>
            <span class="flex items-center min-w-0 gap-2">
              <span
                class="rounded-full size-2.5 shrink-0 bg-n-slate-9"
                :style="row.color ? { backgroundColor: row.color } : undefined"
              />
              <span class="text-[13px] font-bold text-n-slate-12 truncate">
                {{ row.name }}
              </span>
            </span>
            <span class="h-1.5 overflow-hidden rounded-full bg-n-alpha-2">
              <span
                class="block h-full rounded-full bg-n-slate-9"
                :style="{
                  width: `${row.width}%`,
                  backgroundColor: row.color || undefined,
                }"
              />
            </span>
            <span
              class="text-sm font-extrabold text-right tabular-nums text-n-slate-12"
            >
              {{ row.count }}
            </span>
          </li>
        </ol>
      </ReportCard>
      <ReportCard
        class="lg:col-span-5"
        :title="t('REPORTS_UI.LABELS.RESOLUTION_TITLE')"
        :subtitle="t('REPORTS_UI.LABELS.RESOLUTION_SUB')"
      >
        <ReportBarList
          :rows="resolutionBars"
          :empty-text="t('REPORTS_UI.LABELS.EMPTY')"
        />
      </ReportCard>
    </template>

    <!-- Times -->
    <template v-else>
      <ReportCard
        class="lg:col-span-6"
        :title="t('REPORTS_UI.TEAMS.VOLUME_TITLE')"
        :subtitle="t('REPORTS_UI.TEAMS.VOLUME_SUB')"
      >
        <ReportBarList
          :rows="teamVolume"
          :empty-text="t('REPORTS_UI.TEAMS.EMPTY')"
        />
      </ReportCard>
      <ReportCard
        class="lg:col-span-6"
        :title="t('REPORTS_UI.TEAMS.FRT_TITLE')"
        :subtitle="t('REPORTS_UI.TEAMS.FRT_SUB')"
      >
        <ReportBarList
          :rows="frtBars"
          :goal="FRT_GOAL"
          :max="frtMax"
          :empty-text="t('REPORTS_UI.TEAMS.EMPTY')"
        />
      </ReportCard>
    </template>
  </div>
</template>
