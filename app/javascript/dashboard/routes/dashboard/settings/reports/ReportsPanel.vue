<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import startOfDay from 'date-fns/startOfDay';
import subDays from 'date-fns/subDays';
import getUnixTime from 'date-fns/getUnixTime';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import InboxScopeFilter from './components/Filters/InboxScopeFilter.vue';
import { readInboxScope, writeInboxScope } from './helpers/inboxScope';
import PanelOverview from 'dashboard/components-next/reports/panel/PanelOverview.vue';

// Entrada de Relatorios: o painel com abas. A Visao geral e montada aqui; as outras abas
// levam, por enquanto, ao relatorio detalhado de cada assunto.
const DAY = 86400;
const PERIODS = {
  TODAY: { days: 1, hourly: true },
  LAST_7: { days: 7, hourly: false },
  LAST_30: { days: 30, hourly: false },
};

const { t } = useI18n();
const account = useMapGetter('getCurrentAccount');

const periodKey = ref('TODAY');
const inboxId = ref(readInboxScope());

// Periodo anterior = a mesma janela deslocada (hoje ate agora x ontem ate esta hora),
// para a comparacao nao punir o dia que ainda nao acabou.
const period = computed(() => {
  const { days, hourly } = PERIODS[periodKey.value];
  const now = new Date();
  const since = getUnixTime(startOfDay(subDays(now, days - 1)));
  const until = getUnixTime(now);
  const shift = days * DAY;
  return {
    since,
    until,
    prevSince: since - shift,
    prevUntil: until - shift,
    hourly,
    vsKey: periodKey.value,
  };
});

const tabs = computed(() => [
  { key: 'overview', label: t('REPORTS_PANEL.TABS.OVERVIEW'), active: true },
  {
    key: 'agents',
    label: t('REPORTS_PANEL.TABS.AGENTS'),
    to: { name: 'agent_reports_index' },
  },
  {
    key: 'nps',
    label: t('REPORTS_PANEL.TABS.NPS'),
    to: { name: 'nps_reports' },
  },
  {
    key: 'sla',
    label: t('REPORTS_PANEL.TABS.SLA'),
    to: { name: 'sla_reports' },
  },
  { key: 'ai', label: t('REPORTS_PANEL.TABS.AI'), to: { name: 'bot_reports' } },
  {
    key: 'inboxes',
    label: t('REPORTS_PANEL.TABS.INBOXES_LABELS'),
    to: { name: 'inbox_reports_index' },
  },
]);

const pdfFilters = computed(() => ({
  since: period.value.since,
  until: period.value.until,
  inbox_id: inboxId.value || undefined,
}));
</script>

<template>
  <div class="flex flex-col gap-4 pt-6">
    <header
      class="flex flex-col gap-4 p-5 rounded-2xl border border-n-weak bg-n-solid-2"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <p
            class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-10 truncate"
          >
            {{ account?.name }}
          </p>
          <h1 class="m-0 text-3xl font-semibold tracking-tight text-n-slate-12">
            {{ t('REPORTS_PANEL.TITLE') }}
          </h1>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <InboxScopeFilter v-model="inboxId" @change="writeInboxScope" />
          <div
            class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-2"
            role="radiogroup"
          >
            <button
              v-for="(_, key) in PERIODS"
              :key="key"
              type="button"
              role="radio"
              :aria-checked="periodKey === key"
              class="h-8 px-3 m-0 text-sm font-medium rounded-md"
              :class="
                periodKey === key
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
              "
              @click="periodKey = key"
            >
              {{ t(`REPORTS_PANEL.PERIOD.${key}`) }}
            </button>
          </div>
          <DownloadPdfButton report-type="overview" :filters="pdfFilters" />
        </div>
      </div>
      <nav class="flex gap-1 overflow-x-auto -mb-1 pb-1">
        <template v-for="tab in tabs" :key="tab.key">
          <span
            v-if="tab.active"
            class="px-3 py-1.5 text-sm font-semibold rounded-lg whitespace-nowrap bg-n-alpha-2 text-n-slate-12"
            aria-current="page"
          >
            {{ tab.label }}
          </span>
          <router-link
            v-else
            :to="tab.to"
            class="px-3 py-1.5 text-sm font-medium rounded-lg whitespace-nowrap text-n-slate-11 no-underline hover:bg-n-alpha-1 hover:text-n-slate-12"
          >
            {{ tab.label }}
          </router-link>
        </template>
      </nav>
    </header>

    <PanelOverview :period="period" :inbox-id="inboxId" />
  </div>
</template>
