<script setup>
import { ref } from 'vue';
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
  <div class="flex flex-col gap-6 pb-6">
    <StatsLiveReportsContainer :inbox-id="inboxId" />
    <ConversationHeatmapContainer :scope-inbox-id="inboxId" />
    <ResolutionHeatmapContainer :scope-inbox-id="inboxId" />
    <AgentLiveReportContainer :inbox-id="inboxId" />
    <TeamLiveReportContainer :inbox-id="inboxId" />
  </div>
</template>
