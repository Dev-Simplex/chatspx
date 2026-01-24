<script>
import { mapGetters } from 'vuex';
import ReportMetricCard from './ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import PieChart from 'shared/components/charts/PieChart.vue';
import { formatDurationFromSeconds } from 'shared/helpers/timeHelper';

const NPS_SCORES = Array.from({ length: 11 }, (_, i) => ({
  value: i,
  label: i.toString(),
  color: i >= 9 ? '#10b981' : i >= 7 ? '#f59e0b' : '#ef4444',
}));

export default {
  components: { BarChart, PieChart, ReportMetricCard },
  props: {
    filters: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      npsScores: NPS_SCORES,
    };
  },
  computed: {
    ...mapGetters({
      metrics: 'npsResponses/getMetrics',
    }),
    totalCount() {
      return this.metrics.total_count
        ? this.metrics.total_count.toLocaleString()
        : '--';
    },
    npsScore() {
      return this.metrics.nps_score !== undefined
        ? this.metrics.nps_score.toFixed(1)
        : '--';
    },
    responseRate() {
      return this.metrics.response_rate !== undefined
        ? this.metrics.response_rate.toFixed(1)
        : '--';
    },
    promotersPercent() {
      if (!this.metrics.total_count || this.metrics.total_count === 0) return '--';
      const percent = ((this.metrics.promoters_count / this.metrics.total_count) * 100).toFixed(1);
      return `${percent}%`;
    },
    passivesPercent() {
      if (!this.metrics.total_count || this.metrics.total_count === 0) return '--';
      const percent = ((this.metrics.passives_count / this.metrics.total_count) * 100).toFixed(1);
      return `${percent}%`;
    },
    detractorsPercent() {
      if (!this.metrics.total_count || this.metrics.total_count === 0) return '--';
      const percent = ((this.metrics.detractors_count / this.metrics.total_count) * 100).toFixed(1);
      return `${percent}%`;
    },
    blockedCount() {
      return this.metrics.blocked_count
        ? this.metrics.blocked_count.toLocaleString()
        : '--';
    },
    averageResponseDelay() {
      return formatDurationFromSeconds(this.metrics.average_response_delay_seconds) || '--';
    },
    fastestResponseDelay() {
      return formatDurationFromSeconds(this.metrics.fastest_response_delay_seconds) || '--';
    },
    slowestResponseDelay() {
      return formatDurationFromSeconds(this.metrics.slowest_response_delay_seconds) || '--';
    },
    scoreChartData() {
      if (!this.metrics.scores_count || Object.keys(this.metrics.scores_count).length === 0) {
        return {
          labels: [],
          datasets: [],
        };
      }

      const scoresData = this.npsScores.map(score => ({
        label: score.label,
        value: this.metrics.scores_count[score.value] || 0,
        color: score.color,
      }));

      return {
        labels: scoresData.map(s => s.label),
        datasets: [
          {
            label: this.$t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.LABEL', { default: 'Distribuição de Scores' }),
            data: scoresData.map(s => s.value),
            backgroundColor: scoresData.map(s => s.color),
          },
        ],
      };
    },
    scoreChartOptions() {
      return {
        indexAxis: 'x',
        responsive: true,
        plugins: {
          legend: {
            display: false,
          },
          title: {
            display: false,
          },
          tooltip: {
            enabled: true,
            callbacks: {
              label: function(context) {
                return `Score ${context.label}: ${context.parsed.y} ${context.parsed.y === 1 ? 'resposta' : 'respostas'}`;
              },
            },
          },
        },
        scales: {
          x: {
            display: true,
            title: {
              display: true,
              text: this.$t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.X_AXIS', { default: 'Score (0-10)' }),
            },
          },
          y: {
            display: true,
            title: {
              display: true,
              text: this.$t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.Y_AXIS', { default: 'Quantidade' }),
            },
            beginAtZero: true,
          },
        },
      };
    },
    classificationPieData() {
      const breakdown = [
        {
          label: this.$t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' }),
          value: this.metrics.promoters_count || 0,
          color: '#10b981',
        },
        {
          label: this.$t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
          value: this.metrics.passives_count || 0,
          color: '#f59e0b',
        },
        {
          label: this.$t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' }),
          value: this.metrics.detractors_count || 0,
          color: '#ef4444',
        },
      ];

      return {
        labels: breakdown.map(item => item.label),
        datasets: [
          {
            data: breakdown.map(item => item.value),
            backgroundColor: breakdown.map(item => item.color),
          },
        ],
      };
    },
    showPieChart() {
      const total = (this.metrics.promoters_count || 0)
        + (this.metrics.passives_count || 0)
        + (this.metrics.detractors_count || 0);
      return total > 0;
    },
  },
  methods: {
    formatToPercent(value) {
      return value && value !== '--' ? `${value}%` : '--';
    },
  },
};
</script>

<template>
  <div class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-8 flex flex-col gap-6">
    <div class="grid w-full gap-6 sm:grid-cols-2 lg:grid-cols-3">
      <ReportMetricCard
        :label="$t('NPS_REPORTS.METRIC.TOTAL_RESPONSES.LABEL', { default: 'Total de Respostas' })"
        :info-text="$t('NPS_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP', { default: 'Total de respostas NPS recebidas' })"
        :value="totalCount"
      />
      <ReportMetricCard
        :label="$t('NPS_REPORTS.METRIC.NPS_SCORE.LABEL', { default: 'NPS Score' })"
        :info-text="$t('NPS_REPORTS.METRIC.NPS_SCORE.TOOLTIP', { default: 'Net Promoter Score calculado' })"
        :value="npsScore"
      />
      <ReportMetricCard
        :label="$t('NPS_REPORTS.METRIC.RESPONSE_RATE.LABEL', { default: 'Taxa de Resposta' })"
        :info-text="$t('NPS_REPORTS.METRIC.RESPONSE_RATE.TOOLTIP', { default: 'Percentual de respostas em relação aos enviados' })"
        :value="formatToPercent(responseRate)"
      />
    </div>
    <div class="grid w-full gap-6 lg:grid-cols-[1.1fr,0.9fr]">
      <div class="grid gap-4 sm:grid-cols-2">
        <ReportMetricCard
          :label="$t('NPS_REPORTS.METRIC.AVERAGE_RESPONSE_DELAY.LABEL', { default: 'Tempo médio para responder' })"
          :info-text="$t('NPS_REPORTS.METRIC.AVERAGE_RESPONSE_DELAY.TOOLTIP', { default: 'Tempo médio entre o envio da pesquisa e a resposta' })"
          :value="averageResponseDelay"
        />
        <ReportMetricCard
          :label="$t('NPS_REPORTS.METRIC.FASTEST_RESPONSE_DELAY.LABEL', { default: 'Resposta mais rápida' })"
          :info-text="$t('NPS_REPORTS.METRIC.FASTEST_RESPONSE_DELAY.TOOLTIP', { default: 'Menor tempo registrado para responder o NPS' })"
          :value="fastestResponseDelay"
        />
        <ReportMetricCard
          :label="$t('NPS_REPORTS.METRIC.SLOWEST_RESPONSE_DELAY.LABEL', { default: 'Resposta mais lenta' })"
          :info-text="$t('NPS_REPORTS.METRIC.SLOWEST_RESPONSE_DELAY.TOOLTIP', { default: 'Maior tempo registrado para responder o NPS' })"
          :value="slowestResponseDelay"
        />
        <ReportMetricCard
          :label="$t('NPS_REPORTS.METRIC.BLOCKED.LABEL', { default: 'Bloqueados' })"
          :info-text="$t('NPS_REPORTS.METRIC.BLOCKED.TOOLTIP', { default: 'Total de NPS bloqueados por etiquetas' })"
          :value="blockedCount"
        />
      </div>
      <div class="rounded-xl border border-n-slate-6 bg-n-solid-1 p-4">
        <div class="flex items-center justify-between">
          <h3 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
            {{ $t('NPS_REPORTS.CHART.CLASSIFICATION.PIE', { default: 'Distribuição geral' }) }}
          </h3>
          <span class="text-xs text-n-slate-10">
            {{ totalCount !== '--' ? $t('NPS_REPORTS.CHART.TOTAL_TITLE', { default: 'Total', count: totalCount }) : '' }}
          </span>
        </div>
        <div v-if="showPieChart" class="mt-4 h-48 w-full">
          <PieChart :collection="classificationPieData" />
        </div>
        <div v-else class="mt-4 text-sm text-n-slate-11">
          {{ $t('NPS_REPORTS.CHART.NO_DATA', { default: 'Sem dados para distribuição' }) }}
        </div>
        <div class="mt-4 grid gap-2 text-sm">
          <div v-for="item in [
            {
              label: $t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' }),
              value: metrics.promoters_count,
              color: '#10b981',
            },
            {
              label: $t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
              value: metrics.passives_count,
              color: '#f59e0b',
            },
            {
              label: $t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' }),
              value: metrics.detractors_count,
              color: '#ef4444',
            },
          ]" :key="item.label" class="flex items-center justify-between">
            <span class="flex items-center gap-2">
              <span :style="{ backgroundColor: item.color }" class="h-2.5 w-2.5 rounded-full" />
              {{ item.label }}
            </span>
            <span class="font-semibold text-n-slate-12">
              {{ item.value?.toLocaleString() || '0' }}
            </span>
          </div>
        </div>
      </div>
    </div>
    <div v-if="scoreChartData.datasets.length" class="w-full">
      <h3 class="text-xs font-semibold uppercase text-n-slate-11">
        {{ $t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.LABEL', { default: 'Distribuição de Scores' }) }}
      </h3>
      <div class="mt-3 h-64">
        <BarChart :collection="scoreChartData" :chart-options="scoreChartOptions" />
      </div>
    </div>
  </div>
</template>
