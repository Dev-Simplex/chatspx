<script setup>
// Leva os filtros de um componente filho (SummaryReports, AssignmentReports, WootReports) para
// dentro do cartao do ReportHeader, onde ficam os filtros de todas as telas.
</script>

<template>
  <Teleport defer to="#report-header-filters">
    <slot />
  </Teleport>
</template>
