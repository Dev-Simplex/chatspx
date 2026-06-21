<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import SummaryReports from './components/SummaryReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';

const summarReportsRef = ref(null);
const pdfFilters = ref({ from: 0, to: 0, business_hours: false });

const onDownloadClick = () => {
  summarReportsRef.value.downloadReports();
};

const onFilterChange = ({ from, to, businessHours }) => {
  pdfFilters.value = { from, to, business_hours: businessHours };
};
</script>

<template>
  <ReportHeader
    :header-title="$t('TEAM_REPORTS.HEADER')"
    :header-description="$t('TEAM_REPORTS.DESCRIPTION')"
  >
    <div class="flex items-center gap-2">
      <DownloadPdfButton report-type="team" :filters="pdfFilters" />
      <V4Button
        :label="$t('TEAM_REPORTS.DOWNLOAD_TEAM_REPORTS')"
        icon="i-lucide-download"
        size="sm"
        @click="onDownloadClick"
      />
    </div>
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    action-key="summaryReports/fetchTeamSummaryReports"
    getter-key="teams/getTeams"
    fetch-items-key="teams/get"
    summary-key="summaryReports/getTeamSummaryReports"
    type="team"
    @filter-change="onFilterChange"
  />
</template>
