<script setup>
import { ref, watch } from 'vue';
import ReportsHero from './components/ReportsHero.vue';
import ReportsShell from './components/ReportsShell.vue';
import ReportFilterSelector from './components/FilterSelector.vue';
import SummaryReports from './components/SummaryReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';

const summarReportsRef = ref(null);
const pendingFilter = ref(null);

const onDownloadClick = () => {
  summarReportsRef.value.downloadReports();
};

const onFilterChange = payload => {
  if (summarReportsRef.value?.applyFilters) {
    summarReportsRef.value.applyFilters(payload);
  } else {
    pendingFilter.value = payload;
  }
};

watch(summarReportsRef, value => {
  if (value?.applyFilters && pendingFilter.value) {
    value.applyFilters(pendingFilter.value);
    pendingFilter.value = null;
  }
});
</script>

<template>
  <ReportsShell>
    <template #filters>
      <ReportFilterSelector layout="rail" @filter-change="onFilterChange" />
    </template>
    <template #content>
      <ReportsHero
        :title="$t('TEAM_REPORTS.HEADER')"
        :description="$t('TEAM_REPORTS.DESCRIPTION')"
      >
        <template #actions>
          <V4Button
            :label="$t('TEAM_REPORTS.DOWNLOAD_TEAM_REPORTS')"
            icon="i-ph-download-simple"
            size="sm"
            @click="onDownloadClick"
          />
        </template>
      </ReportsHero>

      <SummaryReports
        ref="summarReportsRef"
        :show-filters="false"
        action-key="summaryReports/fetchTeamSummaryReports"
        getter-key="teams/getTeams"
        fetch-items-key="teams/get"
        summary-key="summaryReports/getTeamSummaryReports"
        type="team"
      />
    </template>
  </ReportsShell>
</template>
