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
    :header-title="$t('INBOX_REPORTS.HEADER')"
    :header-description="$t('INBOX_REPORTS.DESCRIPTION')"
  >
    <div class="flex items-center gap-2">
      <DownloadPdfButton report-type="inbox" :filters="pdfFilters" />
      <V4Button
        :label="$t('INBOX_REPORTS.DOWNLOAD_INBOX_REPORTS')"
        icon="i-lucide-download"
        size="sm"
        @click="onDownloadClick"
      />
    </div>
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    action-key="summaryReports/fetchInboxSummaryReports"
    getter-key="inboxes/getInboxes"
    fetch-items-key="inboxes/get"
    summary-key="summaryReports/getInboxSummaryReports"
    type="inbox"
    @filter-change="onFilterChange"
  />
</template>
