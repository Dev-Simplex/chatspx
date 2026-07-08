<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import AssignmentReports from './components/AssignmentReports.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';

const pdfFilters = ref({ from: 0, to: 0, business_hours: false });

const onFilterChange = ({ from, to, businessHours, teamId, inboxId }) => {
  pdfFilters.value = {
    from,
    to,
    business_hours: businessHours,
    team_id: teamId || undefined,
    inbox_id: inboxId || undefined,
  };
};
</script>

<template>
  <ReportHeader
    :header-title="$t('ASSIGNMENT_REPORTS.HEADER')"
    :header-description="$t('ASSIGNMENT_REPORTS.DESCRIPTION')"
  >
    <DownloadPdfButton report-type="agent_assignment" :filters="pdfFilters" />
  </ReportHeader>

  <AssignmentReports @filter-change="onFilterChange" />
</template>
