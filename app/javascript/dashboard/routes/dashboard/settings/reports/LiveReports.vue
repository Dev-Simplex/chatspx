<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ReportVerdict from 'dashboard/components-next/reports/ui/ReportVerdict.vue';
import ReportHeader from './components/ReportHeader.vue';
import ConversationHeatmapContainer from './components/heatmaps/ConversationHeatmapContainer.vue';
import ResolutionHeatmapContainer from './components/heatmaps/ResolutionHeatmapContainer.vue';
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import InboxScopeFilter from './components/Filters/InboxScopeFilter.vue';
import { readInboxScope, writeInboxScope } from './helpers/inboxScope';

// Um recorte para a pagina toda: os cartoes ao vivo e os dois mapas de calor
// seguem esta escolha, em vez de cada cartao ter o seu.
const inboxId = ref(readInboxScope());

// Veredito de agora: tem cliente esperando resposta? (a mesma contagem do cartao "Nao atendidas")
const { t } = useI18n();
const liveMetric = useMapGetter('getAccountConversationMetric');
const liveVerdict = computed(() => {
  const waiting = Number(liveMetric.value?.unattended);
  if (Number.isNaN(waiting) || liveMetric.value?.unattended === undefined)
    return null;
  return waiting > 0
    ? {
        level: waiting > 10 ? 'bad' : 'warn',
        title: t('REPORT.VERDICT.LIVE_BAD_TITLE'),
        text: t('REPORT.VERDICT.LIVE_BAD_TEXT', { n: waiting }, waiting),
      }
    : {
        level: 'good',
        title: t('REPORT.VERDICT.LIVE_GOOD_TITLE'),
        text: t('REPORT.VERDICT.LIVE_GOOD_TEXT'),
      };
});
</script>

<template>
  <ReportHeader :header-title="$t('OVERVIEW_REPORTS.HEADER')">
    <div class="flex items-center gap-2">
      <InboxScopeFilter v-model="inboxId" @change="writeInboxScope" />
      <DownloadPdfButton
        report-type="overview"
        :filters="{ inbox_id: inboxId || undefined }"
      />
    </div>
  </ReportHeader>
  <ReportVerdict v-if="liveVerdict" :verdict="liveVerdict" />
  <div class="flex flex-col gap-4">
    <StatsLiveReportsContainer :inbox-id="inboxId" />
    <ConversationHeatmapContainer :scope-inbox-id="inboxId" />
    <ResolutionHeatmapContainer :scope-inbox-id="inboxId" />
    <AgentLiveReportContainer :inbox-id="inboxId" />
    <TeamLiveReportContainer :inbox-id="inboxId" />
  </div>
</template>
