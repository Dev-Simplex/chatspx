<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import { useStageColor } from './composables/useStageColor';

const props = defineProps({
  funnelId: { type: Number, required: true },
});

const store = useStore();
const { t } = useI18n();
const { accent } = useStageColor();

const isLoading = ref(false);
const stats = computed(() =>
  store.getters['kanban/getFunnelStats'](props.funnelId)
);

const refresh = async () => {
  if (!props.funnelId) return;
  isLoading.value = true;
  try {
    await store.dispatch('kanban/fetchFunnelStats', {
      funnelId: props.funnelId,
    });
  } finally {
    isLoading.value = false;
  }
};
watch(() => props.funnelId, refresh, { immediate: true });

const totals = computed(() => stats.value?.totals || {});
const baseline = computed(() => stats.value?.baseline || null);
const stages = computed(() => stats.value?.stages || []);
const workload = computed(() => stats.value?.workload || []);

// Delta of total cards vs yesterday's snapshot (if available).
const cardsDelta = computed(() => {
  if (!baseline.value || baseline.value.cards == null) return null;
  return (totals.value.cards || 0) - baseline.value.cards;
});

const numberCards = computed(() => [
  {
    key: 'cards',
    label: t('KANBAN.DASHBOARD.CARDS'),
    value: totals.value.cards || 0,
    delta: cardsDelta.value,
  },
  {
    key: 'open',
    label: t('KANBAN.DASHBOARD.OPEN'),
    value: totals.value.by_status?.open || 0,
  },
  {
    key: 'resolved_today',
    label: t('KANBAN.DASHBOARD.RESOLVED_TODAY'),
    value: totals.value.resolved_today || 0,
  },
  {
    key: 'created_today',
    label: t('KANBAN.DASHBOARD.CREATED_TODAY'),
    value: totals.value.created_today || 0,
  },
  {
    key: 'unassigned',
    label: t('KANBAN.DASHBOARD.UNASSIGNED'),
    value: totals.value.unassigned || 0,
  },
  {
    key: 'overdue',
    label: t('KANBAN.DASHBOARD.OVERDUE'),
    value: totals.value.overdue || 0,
    danger: true,
  },
]);

const stageChart = computed(() => ({
  labels: stages.value.map(s => s.name),
  datasets: [
    {
      label: t('KANBAN.DASHBOARD.CARDS'),
      data: stages.value.map(s => s.count),
      backgroundColor: stages.value.map(s => accent(s.color)),
      borderRadius: 4,
    },
  ],
}));

const workloadChart = computed(() => ({
  labels: workload.value.map(w => w.name || `#${w.assignee_id}`),
  datasets: [
    {
      label: t('KANBAN.DASHBOARD.CARDS'),
      data: workload.value.map(w => w.count),
      backgroundColor: '#1f93ff',
      borderRadius: 4,
    },
  ],
}));

const formatAge = seconds => {
  if (!seconds || seconds <= 0) return '—';
  const h = Math.floor(seconds / 3600);
  if (h >= 24) {
    const d = Math.floor(h / 24);
    return `${d}d ${h % 24}h`;
  }
  if (h >= 1) return `${h}h`;
  return `${Math.max(1, Math.floor(seconds / 60))}min`;
};

// Export the per-stage table as CSV (client-side).
const exportCsv = () => {
  const header = [
    'stage',
    'cards',
    'avg_age_seconds',
    'unassigned',
    'overdue',
    'sla_hours',
  ];
  const rows = stages.value.map(s => [
    s.name,
    s.count,
    s.avg_age_seconds ?? '',
    s.unassigned,
    s.overdue,
    s.sla_hours ?? '',
  ]);
  const csv = [header, ...rows]
    .map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(','))
    .join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `funnel-${props.funnelId}-stats.csv`;
  link.click();
  URL.revokeObjectURL(url);
};
</script>

<template>
  <div
    class="dashboard-view flex h-full w-full flex-col overflow-y-auto bg-n-background p-4"
  >
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.DASHBOARD.TITLE') }}
      </h2>
      <div class="flex items-center gap-2">
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-download"
          @click="exportCsv"
        >
          <span class="ml-1">{{ t('KANBAN.DASHBOARD.EXPORT') }}</span>
        </Button>
        <Button
          size="sm"
          variant="ghost"
          icon="i-lucide-refresh-cw"
          :is-loading="isLoading"
          @click="refresh"
        >
          <span class="ml-1">{{ t('KANBAN.DASHBOARD.REFRESH') }}</span>
        </Button>
      </div>
    </div>

    <!-- Numbers row -->
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
      <div
        v-for="card in numberCards"
        :key="card.key"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <p
          class="text-[11px] font-medium uppercase tracking-wide text-n-slate-10"
        >
          {{ card.label }}
        </p>
        <p
          class="mt-1 text-2xl font-bold"
          :class="
            card.danger && card.value ? 'text-n-ruby-11' : 'text-n-slate-12'
          "
        >
          {{ card.value }}
        </p>
        <p
          v-if="card.delta != null && card.delta !== 0"
          class="text-[11px] font-medium"
          :class="card.delta > 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{ card.delta > 0 ? '▲' : '▼' }} {{ Math.abs(card.delta) }}
          {{ t('KANBAN.DASHBOARD.VS_YESTERDAY') }}
        </p>
      </div>
    </div>

    <!-- Charts -->
    <div class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
        <p class="mb-2 text-xs font-semibold text-n-slate-11">
          {{ t('KANBAN.DASHBOARD.BY_STAGE') }}
        </p>
        <div class="h-56">
          <BarChart :collection="stageChart" />
        </div>
      </div>
      <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
        <p class="mb-2 text-xs font-semibold text-n-slate-11">
          {{ t('KANBAN.DASHBOARD.WORKLOAD') }}
        </p>
        <div v-if="workload.length" class="h-56">
          <BarChart :collection="workloadChart" />
        </div>
        <p v-else class="py-10 text-center text-xs text-n-slate-10">
          {{ t('KANBAN.DASHBOARD.NO_WORKLOAD') }}
        </p>
      </div>
    </div>

    <!-- Aging / SLA table -->
    <div class="mt-4 rounded-xl border border-n-weak bg-n-solid-1 p-3">
      <p class="mb-2 text-xs font-semibold text-n-slate-11">
        {{ t('KANBAN.DASHBOARD.AGING') }}
      </p>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[520px] text-sm">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-[11px] uppercase tracking-wide text-n-slate-10"
            >
              <th class="py-1.5 pr-3">{{ t('KANBAN.DASHBOARD.STAGE') }}</th>
              <th class="py-1.5 pr-3">{{ t('KANBAN.DASHBOARD.CARDS') }}</th>
              <th class="py-1.5 pr-3">{{ t('KANBAN.DASHBOARD.AVG_AGE') }}</th>
              <th class="py-1.5 pr-3">
                {{ t('KANBAN.DASHBOARD.UNASSIGNED') }}
              </th>
              <th class="py-1.5 pr-3">{{ t('KANBAN.DASHBOARD.OVERDUE') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="stage in stages"
              :key="stage.id"
              class="border-b border-n-weak/60"
            >
              <td class="py-1.5 pr-3">
                <span class="inline-flex items-center gap-2">
                  <span
                    class="size-2 rounded-full"
                    :style="{ backgroundColor: accent(stage.color) }"
                  />
                  {{ stage.name }}
                </span>
              </td>
              <td class="py-1.5 pr-3 font-medium text-n-slate-12">
                {{ stage.count }}
              </td>
              <td class="py-1.5 pr-3 text-n-slate-11">
                {{ formatAge(stage.avg_age_seconds) }}
              </td>
              <td class="py-1.5 pr-3 text-n-slate-11">
                {{ stage.unassigned }}
              </td>
              <td
                class="py-1.5 pr-3"
                :class="
                  stage.overdue
                    ? 'font-semibold text-n-ruby-11'
                    : 'text-n-slate-11'
                "
              >
                {{ stage.overdue }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div
      v-if="!stats && !isLoading"
      class="flex flex-1 items-center justify-center"
    >
      <div class="flex flex-col items-center text-center text-n-slate-10">
        <Icon icon="i-lucide-bar-chart-3" class="mb-2 size-8" />
        <p class="text-sm">{{ t('KANBAN.DASHBOARD.EMPTY') }}</p>
      </div>
    </div>
  </div>
</template>
