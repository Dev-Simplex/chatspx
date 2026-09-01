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

const onFilterChange = ({ from, to, businessHours, inboxId }) => {
  pdfFilters.value = {
    from,
    to,
    business_hours: businessHours,
    inbox_id: inboxId || undefined,
  };
};
</script>

<template>
  <ReportHeader
    :header-title="$t('AGENT_REPORTS.HEADER')"
    :header-description="$t('AGENT_REPORTS.DESCRIPTION')"
  >
    <div class="flex items-center gap-2">
      <DownloadPdfButton report-type="agent" :filters="pdfFilters" />
      <V4Button
        :label="$t('AGENT_REPORTS.DOWNLOAD_AGENT_REPORTS')"
        icon="i-lucide-download"
        size="sm"
        @click="onDownloadClick"
      />
    </div>
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    action-key="summaryReports/fetchAgentSummaryReports"
    getter-key="agents/getAgents"
    fetch-items-key="agents/get"
    summary-key="summaryReports/getAgentSummaryReports"
    type="agent"
    @filter-change="onFilterChange"
  />
</template>
