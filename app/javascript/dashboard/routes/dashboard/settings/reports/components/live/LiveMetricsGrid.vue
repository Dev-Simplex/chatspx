<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportMetricCard from '../ReportMetricCard.vue';

const props = defineProps({
  metrics: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const metricCards = computed(() => [
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.ONLINE_USERS'),
    value: props.metrics.onlineUsers || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.ONLINE_USERS'),
    color: 'teal',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.OFFLINE_USERS'),
    value: props.metrics.offlineUsers || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.OFFLINE_USERS'),
    color: 'slate',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.ABSENT_USERS'),
    value: props.metrics.absentUsers || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.ABSENT_USERS'),
    color: 'amber',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.USERS_WITH_SERVICE'),
    value: props.metrics.usersWithService || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.USERS_WITH_SERVICE'),
    color: 'teal',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.USERS_WITHOUT_SERVICE'),
    value: props.metrics.usersWithoutService || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.USERS_WITHOUT_SERVICE'),
    color: 'amber',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.CALLS_IN_QUEUE'),
    value: props.metrics.callsInQueue || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.CALLS_IN_QUEUE'),
    color: 'ruby',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.OPEN_CALLS'),
    value: props.metrics.openCalls || '0',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.OPEN_CALLS'),
    color: 'brand',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.AVG_OPEN_CALLS_TIME'),
    value: props.metrics.avgOpenCallsTime || '00:00:00',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.AVG_OPEN_CALLS_TIME'),
    color: 'slate',
  },
  {
    label: t('LIVE_REPORTS.SUMMARY.METRICS.TME_FIRST_SERVICE'),
    value: props.metrics.tmeFirstService || '00:00:00',
    infoText: t('LIVE_REPORTS.SUMMARY.METRICS.TME_FIRST_SERVICE'),
    color: 'slate',
  },
]);
</script>

<template>
  <transition-group
    name="metric-grid"
    tag="div"
    class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
  >
    <div
      v-for="(metric, index) in metricCards"
      :key="index"
      class="metric-card-wrapper"
      :style="{ animationDelay: `${index * 0.05}s` }"
    >
      <ReportMetricCard
        :label="metric.label"
        :value="metric.value"
        :info-text="metric.infoText"
      />
    </div>
  </transition-group>
</template>

<style scoped>
.metric-card-wrapper {
  animation: slideInUp 0.4s ease-out both;
}

@keyframes slideInUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.metric-grid-enter-active,
.metric-grid-leave-active {
  transition: all 0.3s ease;
}

.metric-grid-enter-from {
  opacity: 0;
  transform: scale(0.9);
}

.metric-grid-leave-to {
  opacity: 0;
  transform: scale(0.9);
}

.metric-grid-move {
  transition: transform 0.3s ease;
}
</style>
