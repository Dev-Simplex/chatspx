<script setup>
// KANBAN-P2-05: 4 métricas no header (total, valor pipeline, aging médio, win rate).
// Cache 60s no backend. Fetch via Pinia store useKanbanMetricsStore.
// Em mobile (<sm) só mostra total + win rate (mais relevantes).
import { computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanMetricsStore } from 'dashboard/store/pinia/kanban/metrics';

const props = defineProps({
  funnelId: { type: [Number, String, null], default: null },
});

const { t } = useI18n();
const metricsStore = useKanbanMetricsStore();
const { byKanban } = storeToRefs(metricsStore);

const metrics = computed(() => {
  if (!props.funnelId) return null;
  return byKanban.value[Number(props.funnelId)] || null;
});

const fetch = () => {
  if (props.funnelId) metricsStore.fetchMetrics(props.funnelId);
};

watch(() => props.funnelId, fetch);
onMounted(fetch);

const totalDisplay = computed(() => {
  if (!metrics.value) return '—';
  return new Intl.NumberFormat('pt-BR').format(metrics.value.total || 0);
});

const formatBrl = cents => {
  if (cents <= 0) return '—';
  const v = cents / 100;
  if (v >= 1000) {
    return `R$ ${(v / 1000).toFixed(1)}k`;
  }
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(v);
};

const pipelineDisplay = computed(() => {
  if (!metrics.value) return '—';
  return formatBrl(Number(metrics.value.pipelineValueCents || 0));
});

// P3-06: pipeline ponderado por probability.
const weightedPipelineDisplay = computed(() => {
  if (!metrics.value) return '';
  const cents = Number(
    metrics.value.weightedPipelineValueCents ||
      metrics.value.weighted_pipeline_value_cents ||
      0
  );
  if (cents <= 0) return '';
  return formatBrl(cents);
});

const agingDisplay = computed(() => {
  if (!metrics.value) return '—';
  const v = Number(metrics.value.averageAgingDays || 0);
  return v === 0 ? '0d' : `${v.toFixed(1)}d`;
});

const winRateDisplay = computed(() => {
  if (!metrics.value) return '—';
  const v = metrics.value.winRate;
  if (v == null) return '—';
  return `${Math.round(Number(v))}%`;
});
</script>

<template>
  <div
    class="flex items-center gap-3 text-xs text-slate-600 dark:text-slate-300"
    :aria-label="t('KANBAN.METRICS_ARIA')"
  >
    <span
      class="inline-flex items-center gap-1.5"
      :title="t('KANBAN.METRICS.TOTAL_TOOLTIP')"
    >
      <Icon icon="i-lucide-layers" class="size-3.5 text-slate-400" />
      <span
        class="font-semibold tabular-nums text-slate-800 dark:text-slate-100"
      >
        {{ totalDisplay }}
      </span>
      <span class="hidden md:inline">{{
        t('KANBAN.METRICS.TOTAL_LABEL')
      }}</span>
    </span>

    <span
      class="hidden sm:inline-flex items-center gap-1.5"
      :title="t('KANBAN.METRICS.PIPELINE_TOOLTIP')"
    >
      <Icon icon="i-lucide-dollar-sign" class="size-3.5 text-emerald-500" />
      <span
        class="font-semibold tabular-nums text-slate-800 dark:text-slate-100"
      >
        {{ pipelineDisplay }}
      </span>
      <span
        v-if="weightedPipelineDisplay"
        class="hidden lg:inline-flex items-center gap-1 text-slate-500 dark:text-slate-400"
        :title="t('KANBAN.METRICS_EXTRA.WEIGHTED_TOOLTIP')"
      >
        ·
        {{
          t('KANBAN.METRICS_EXTRA.WEIGHTED_PIPELINE', {
            value: weightedPipelineDisplay,
          })
        }}
      </span>
    </span>

    <span
      class="hidden sm:inline-flex items-center gap-1.5"
      :title="t('KANBAN.METRICS.AGING_TOOLTIP')"
    >
      <Icon icon="i-lucide-clock" class="size-3.5 text-amber-500" />
      <span
        class="font-semibold tabular-nums text-slate-800 dark:text-slate-100"
      >
        {{ agingDisplay }}
      </span>
    </span>

    <span
      class="inline-flex items-center gap-1.5"
      :title="t('KANBAN.METRICS.WIN_RATE_TOOLTIP')"
    >
      <Icon icon="i-lucide-trending-up" class="size-3.5 text-iris-500" />
      <span
        class="font-semibold tabular-nums text-slate-800 dark:text-slate-100"
      >
        {{ winRateDisplay }}
      </span>
      <span class="hidden md:inline">{{
        t('KANBAN.METRICS.WIN_RATE_LABEL')
      }}</span>
    </span>
  </div>
</template>
