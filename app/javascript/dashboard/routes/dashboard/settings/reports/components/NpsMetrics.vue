<script>
import { mapGetters } from 'vuex';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import ReportMetricCard from './ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';

function scoreColor(i) {
  if (i >= 9) return '#10b981';
  if (i >= 7) return '#f59e0b';
  return '#ef4444';
}

const NPS_SCORES = Array.from({ length: 11 }, (_, i) => ({
  value: i,
  label: i.toString(),
  color: scoreColor(i),
}));

export default {
  components: { BarChart, ReportMetricCard },
  props: {
    // eslint-disable-next-line vue/no-unused-properties
    filters: {
      type: Object,
      required: true,
    },
  },
  setup() {
    const { signalByMetric } = useReportNarrative();
    return { signalByMetric };
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
    hasData() {
      return Boolean(this.metrics.total_count);
    },
    // Amostra baixa: há respostas, mas abaixo do mínimo confiável (reliable=false).
    isLowSample() {
      return this.hasData && this.metrics.reliable === false;
    },
    // Suprime a pílula vermelha/verde quando a amostra é baixa (N volátil).
    npsSignal() {
      if (!this.hasData || this.isLowSample) return null;
      return this.signalByMetric(this.metrics.signals, 'nps');
    },
    // Tendência em PONTOS vs período anterior → { text, tone } p/ o card.
    npsTrend() {
      const delta = this.metrics.nps_delta;
      if (delta === null || delta === undefined || delta === 0) return null;
      const sign = delta > 0 ? '▲ +' : '▼ ';
      return {
        text: this.$t('NPS_REPORTS.METRIC.NPS_SCORE.TREND', {
          value: `${sign}${delta}`,
          default: `${sign}${delta} pts vs período anterior`,
        }),
        tone: delta > 0 ? 'good' : 'bad',
      };
    },
    lowSampleBadge() {
      if (!this.isLowSample) return '';
      return this.$t('NPS_REPORTS.LOW_SAMPLE', {
        count: this.metrics.total_count,
        min: this.metrics.min_sample,
        default: `Amostra baixa: ${this.metrics.total_count} respostas (mínimo ${this.metrics.min_sample}). Resultado pouco confiável.`,
      });
    },
    totalCount() {
      return this.hasData ? this.metrics.total_count.toLocaleString() : '--';
    },
    // NPS inteiro (−100..+100), padrão de mercado; '--' sem dados.
    npsScore() {
      return this.hasData ? String(Math.round(this.metrics.nps_score)) : '--';
    },
    responseRate() {
      return this.hasData ? this.metrics.response_rate.toFixed(1) : '--';
    },
    // Percentuais vêm do backend (fonte única); fallback para cálculo local.
    promotersPercent() {
      return this.bandPercent('promoters');
    },
    passivesPercent() {
      return this.bandPercent('passives');
    },
    detractorsPercent() {
      return this.bandPercent('detractors');
    },
    blockedCount() {
      return this.metrics.blocked_count
        ? this.metrics.blocked_count.toLocaleString()
        : '--';
    },
    detractorFollowup() {
      return this.metrics.detractor_followup || {};
    },
    // Só exibe o card quando houve detratores no período.
    hasDetractorFollowup() {
      return Boolean(this.detractorFollowup.total);
    },
    // Tempo médio até um agente responder um detrator: "1h 10min" / "45min" / "—".
    detractorFollowupTime() {
      const seconds = this.detractorFollowup.avg_followup_seconds;
      if (seconds === null || seconds === undefined) return '—';
      if (seconds < 60) return `${Math.round(seconds)}s`;
      const totalMinutes = Math.floor(seconds / 60);
      const hours = Math.floor(totalMinutes / 60);
      const minutes = totalMinutes % 60;
      if (hours > 0)
        return minutes > 0 ? `${hours}h ${minutes}min` : `${hours}h`;
      return `${minutes}min`;
    },
    detractorFollowupSummary() {
      return this.$t('NPS_REPORTS.METRIC.DETRACTOR_FOLLOWUP.SUMMARY', {
        followedUp: this.detractorFollowup.followed_up_count || 0,
        awaiting: this.detractorFollowup.awaiting_count || 0,
        default: `${this.detractorFollowup.followed_up_count || 0} respondidos / ${this.detractorFollowup.awaiting_count || 0} aguardando`,
      });
    },
    detractorFollowupTooltip() {
      return this.$t('NPS_REPORTS.METRIC.DETRACTOR_FOLLOWUP.TOOLTIP', {
        default:
          "Tempo médio até um agente responder um detrator (0-6) após a nota. 'Aguardando' = detratores ainda sem retorno humano.",
      });
    },
    // Tooltip do card "Bloqueados": inclui o detalhamento por etiqueta.
    blockedTooltip() {
      const base = this.$t('NPS_REPORTS.METRIC.BLOCKED.TOOLTIP', {
        default: 'Total de NPS bloqueados por etiquetas',
      });
      const byLabel = this.metrics.blocked_by_label_count || {};
      const entries = Object.entries(byLabel);
      if (!entries.length) return base;
      const detail = entries
        .sort((a, b) => b[1] - a[1])
        .map(([label, count]) => `${label}: ${count}`)
        .join(' · ');
      return `${base}\n${detail}`;
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
            label: this.$t('NPS_REPORTS.METRIC.SCORE_DISTRIBUTION.LABEL', {
              default: 'Distribuição de Scores',
            }),
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
              label: context => {
                const total = Object.values(
                  this.metrics.scores_count || {}
                ).reduce((sum, n) => sum + n, 0);
                const count = context.parsed.y;
                const share = total ? Math.round((count / total) * 100) : 0;
                return this.$t('NPS_REPORTS.CHART.TOOLTIP', {
                  score: context.label,
                  count,
                  share,
                  default: `Nota ${context.label}: ${count} (${share}%)`,
                });
              },
            },
          },
        },
        scales: {
          x: {
            display: true,
            title: {
              display: true,
              text: this.$t('NPS_REPORTS.CHART.X_AXIS', {
                default: 'Nota (0-10)',
              }),
            },
          },
          y: {
            display: true,
            title: {
              display: true,
              text: this.$t('NPS_REPORTS.CHART.Y_AXIS', {
                default: 'Quantidade',
              }),
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
    // Percentual da faixa a partir do backend (fonte única do cálculo do NPS),
    // com fallback local para contas cujo payload ainda não traz *_pct.
    bandPercent(band) {
      if (!this.hasData) return '--';
      const pct = this.metrics[`${band}_pct`];
      if (pct !== undefined && pct !== null) return `${pct.toFixed(1)}%`;
      const count = this.metrics[`${band}_count`] || 0;
      return `${((count / this.metrics.total_count) * 100).toFixed(1)}%`;
    },
  },
};
</script>

<template>
  <div
    class="flex-col lg:flex-row flex flex-wrap mx-0 rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-6 gap-4 shadow-sm"
  >
    <div
      v-if="isLowSample"
      class="w-full flex items-center gap-2 rounded-lg border border-n-amber-7 bg-n-amber-3 px-3 py-2 text-xs font-medium text-n-amber-11"
    >
      {{ lowSampleBadge }}
    </div>
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
      :signal="npsSignal"
      :trend="npsTrend"
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
      :info-text="blockedTooltip"
      :value="blockedCount"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />
    <ReportMetricCard
      v-if="hasDetractorFollowup"
      :label="
        $t('NPS_REPORTS.METRIC.DETRACTOR_FOLLOWUP.LABEL', {
          default: 'Follow-up de detratores',
        })
      "
      :info-text="detractorFollowupTooltip"
      :value="detractorFollowupTime"
      :trend="{ text: detractorFollowupSummary, tone: 'flat' }"
      class="xs:w-full sm:max-w-[50%] lg:w-1/6 lg:max-w-[16%]"
    />

    <div
      v-if="
        metrics.total_count &&
        metrics.scores_count &&
        Object.keys(metrics.scores_count).length > 0
      "
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
      <div
        class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-n-slate-11"
      >
        <span class="inline-flex items-center gap-1">
          <span class="inline-block w-2.5 h-2.5 rounded-sm bg-[#ef4444]" />
          {{
            $t('NPS_REPORTS.CHART.LEGEND.DETRACTORS', {
              default: 'Detratores (0-6)',
            })
          }}
        </span>
        <span class="inline-flex items-center gap-1">
          <span class="inline-block w-2.5 h-2.5 rounded-sm bg-[#f59e0b]" />
          {{
            $t('NPS_REPORTS.CHART.LEGEND.PASSIVES', {
              default: 'Passivos (7-8)',
            })
          }}
        </span>
        <span class="inline-flex items-center gap-1">
          <span class="inline-block w-2.5 h-2.5 rounded-sm bg-[#10b981]" />
          {{
            $t('NPS_REPORTS.CHART.LEGEND.PROMOTERS', {
              default: 'Promotores (9-10)',
            })
          }}
        </span>
      </div>
    </div>
  </div>
</template>
