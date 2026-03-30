<script>
import { mapGetters } from 'vuex';
import ReportMetricCard from './ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';

const NPS_SCORES = Array.from({ length: 11 }, (_, i) => ({
  value: i,
  label: i.toString(),
  color: i >= 9 ? '#10b981' : i >= 7 ? '#f59e0b' : '#ef4444', // Verde para promotores, amarelo para passivos, vermelho para detratores
}));

export default {
  components: { BarChart, ReportMetricCard },
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
      console.log('NpsMetrics: totalCount computed - metrics:', this.metrics);
      console.log(
        'NpsMetrics: totalCount computed - total_count:',
        this.metrics.total_count
      );
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
      if (!this.metrics.total_count || this.metrics.total_count === 0)
        return '--';
      const percent = (
        (this.metrics.promoters_count / this.metrics.total_count) *
        100
      ).toFixed(1);
      return `${percent}%`;
    },
    passivesPercent() {
      if (!this.metrics.total_count || this.metrics.total_count === 0)
        return '--';
      const percent = (
        (this.metrics.passives_count / this.metrics.total_count) *
        100
      ).toFixed(1);
      return `${percent}%`;
    },
    detractorsPercent() {
      if (!this.metrics.total_count || this.metrics.total_count === 0)
        return '--';
      const percent = (
        (this.metrics.detractors_count / this.metrics.total_count) *
        100
      ).toFixed(1);
      return `${percent}%`;
    },
    blockedCount() {
      return this.metrics.blocked_count
        ? this.metrics.blocked_count.toLocaleString()
        : '--';
    },
    chartData() {
      if (
        !this.metrics.scores_count ||
        Object.keys(this.metrics.scores_count).length === 0
      ) {
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
            label: 'Distribuição de Scores',
            data: scoresData.map(s => s.value),
            backgroundColor: scoresData.map(s => s.color),
          },
        ],
      };
    },
    chartOptions() {
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
              label: function (context) {
                return `Score ${context.label}: ${context.parsed.y} respostas`;
              },
            },
          },
        },
        scales: {
          x: {
            display: true,
            title: {
              display: true,
              text: 'Score (0-10)',
            },
          },
          y: {
            display: true,
            title: {
              display: true,
              text: 'Quantidade',
            },
            beginAtZero: true,
          },
        },
      };
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
  <div
    class="flex-col lg:flex-row flex flex-wrap mx-0 rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-6 gap-4 shadow-sm"
  >
    <ReportMetricCard
      :label="
        $t('NPS_REPORTS.METRIC.TOTAL_RESPONSES.LABEL', {
          default: 'Total de Respostas',
        })
      "
      :info-text="
        $t('NPS_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP', {
          default: 'Total de respostas NPS recebidas',
        })
      "
      :value="totalCount"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="
        $t('NPS_REPORTS.METRIC.NPS_SCORE.LABEL', { default: 'NPS Score' })
      "
      :info-text="
        $t('NPS_REPORTS.METRIC.NPS_SCORE.TOOLTIP', {
          default: 'Net Promoter Score calculado',
        })
      "
      :value="npsScore"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="
        $t('NPS_REPORTS.METRIC.RESPONSE_RATE.LABEL', {
          default: 'Taxa de Resposta',
        })
      "
      :info-text="
        $t('NPS_REPORTS.METRIC.RESPONSE_RATE.TOOLTIP', {
          default: 'Percentual de respostas em relação aos enviados',
        })
      "
      :value="formatToPercent(responseRate)"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="
        $t('NPS_REPORTS.METRIC.PROMOTERS.LABEL', { default: 'Promotores' })
      "
      :info-text="
        $t('NPS_REPORTS.METRIC.PROMOTERS.TOOLTIP', {
          default: 'Percentual de promotores (9-10)',
        })
      "
      :value="promotersPercent"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="$t('NPS_REPORTS.METRIC.PASSIVES.LABEL', { default: 'Passivos' })"
      :info-text="
        $t('NPS_REPORTS.METRIC.PASSIVES.TOOLTIP', {
          default: 'Percentual de passivos (7-8)',
        })
      "
      :value="passivesPercent"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="
        $t('NPS_REPORTS.METRIC.DETRACTORS.LABEL', { default: 'Detratores' })
      "
      :info-text="
        $t('NPS_REPORTS.METRIC.DETRACTORS.TOOLTIP', {
          default: 'Percentual de detratores (0-6)',
        })
      "
      :value="detractorsPercent"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      :label="$t('NPS_REPORTS.METRIC.BLOCKED.LABEL', { default: 'Bloqueados' })"
      :info-text="
        $t('NPS_REPORTS.METRIC.BLOCKED.TOOLTIP', {
          default: 'Total de NPS bloqueados por etiquetas',
        })
      "
      :value="blockedCount"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />

    <div
      v-if="
        metrics.total_count &&
        metrics.scores_count &&
        Object.keys(metrics.scores_count).length > 0
      "
      ref="npsBarChart"
      class="w-full md:w-1/2 md:max-w-[50%] flex-1 rtl:[direction:initial]"
    >
      <h3
        class="flex items-center m-0 text-xs font-medium md:text-sm text-n-slate-12 mb-2"
      >
        {{
          $t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.LABEL', {
            default: 'Distribuição de Scores',
          })
        }}
      </h3>
      <div class="mt-2 h-64">
        <BarChart :collection="chartData" :chart-options="chartOptions" />
      </div>
    </div>
  </div>
</template>
