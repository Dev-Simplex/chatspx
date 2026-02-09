<script setup>
import ReportsHero from './components/ReportsHero.vue';
import ReportsShell from './components/ReportsShell.vue';
import ConversationHeatmapContainer from './components/heatmaps/ConversationHeatmapContainer.vue';
import ResolutionHeatmapContainer from './components/heatmaps/ResolutionHeatmapContainer.vue';
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';
</script>

<template>
  <ReportsShell>
    <template #content>
      <ReportsHero :title="$t('OVERVIEW_REPORTS.HEADER')" />
      <div class="grid grid-cols-1 gap-6 pb-6 xl:grid-cols-12">
        <div class="xl:col-span-12">
          <StatsLiveReportsContainer />
        </div>
        <div class="xl:col-span-7">
          <ConversationHeatmapContainer />
        </div>
        <div class="xl:col-span-5">
          <ResolutionHeatmapContainer />
        </div>
        <div class="xl:col-span-7">
          <AgentLiveReportContainer />
        </div>
        <div class="xl:col-span-5">
          <TeamLiveReportContainer />
        </div>
      </div>
    </template>
  </ReportsShell>
</template>
