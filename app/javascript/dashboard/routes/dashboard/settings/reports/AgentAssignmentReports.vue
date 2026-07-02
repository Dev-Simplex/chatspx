<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import AssignmentReports from './components/AssignmentReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';

const assignmentReportsRef = ref(null);

const onDownloadClick = () => {
  assignmentReportsRef.value.downloadReports();
};
</script>

<template>
  <ReportHeader
    :header-title="$t('ASSIGNMENT_REPORTS.HEADER')"
    :header-description="$t('ASSIGNMENT_REPORTS.DESCRIPTION')"
  >
    <V4Button
      :label="$t('ASSIGNMENT_REPORTS.DOWNLOAD')"
      icon="i-lucide-download"
      size="sm"
      @click="onDownloadClick"
    />
  </ReportHeader>

  <AssignmentReports ref="assignmentReportsRef" />
</template>
