<script setup>
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';
import { formatPercent } from 'dashboard/helper/reportFormat';
import { useMapGetter } from 'dashboard/composables/store';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import CsatMetricCard from './CsatMetricCard.vue';
import CsatRatingDistribution from './CsatRatingDistribution.vue';

const metrics = useMapGetter('csat/getMetrics');
const { signalByMetric } = useReportNarrative();
const csatSignal = computed(() =>
  signalByMetric(metrics.value.signals, 'csat')
);
const ratingPercentage = useMapGetter('csat/getRatingPercentage');
const ratingCount = useMapGetter('csat/getRatingCount');
const satisfactionScore = useMapGetter('csat/getSatisfactionScore');
const responseRate = useMapGetter('csat/getResponseRate');
const uiFlags = useMapGetter('csat/getUIFlags');

const isLoading = computed(() => uiFlags.value.isFetchingMetrics);

const responseCount = computed(() =>
  metrics.value.totalResponseCount
    ? metrics.value.totalResponseCount.toLocaleString()
    : '0'
);

// As notas em frases: quantas, quantos ficaram satisfeitos (4 e 5) e quantos nao (1 e 2), e quantos responderam.
const countOf = (...ratings) =>
  ratings.reduce((sum, r) => sum + Number(ratingCount.value?.[r] || 0), 0);
const satisfied = computed(() => countOf(4, 5).toLocaleString());
const unhappy = computed(() => countOf(1, 2).toLocaleString());
const hasResponses = computed(
  () => Number(metrics.value.totalResponseCount) > 0
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="hasResponses && !isLoading"
      class="rounded-2xl border border-n-weak bg-n-solid-2 px-6 py-5"
    >
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ $t('REPORT.PLAIN_SUMMARY.TITLE') }}
      </h3>
      <ul
        class="mt-3 flex flex-col gap-3 text-base leading-relaxed text-n-slate-12"
      >
        <li class="flex gap-3">
          <span class="i-lucide-smile size-5 mt-1 shrink-0 text-n-brand" />
          <span class="min-w-0">
            <I18nT keypath="CSAT_REPORTS.PLAIN_SUMMARY.SCORE" tag="span">
              <template #total>
                <strong>{{ responseCount }}</strong>
              </template>
              <template #satisfied>
                <strong>{{ satisfied }}</strong>
              </template>
              <template #percent>
                <strong>{{ formatPercent(satisfactionScore) }}</strong>
              </template>
              <template #unhappy>
                <strong>{{ unhappy }}</strong>
              </template>
            </I18nT>
          </span>
        </li>
        <li class="flex gap-3">
          <span class="i-lucide-send size-5 mt-1 shrink-0 text-n-brand" />
          <span class="min-w-0">
            <I18nT keypath="CSAT_REPORTS.PLAIN_SUMMARY.RATE" tag="span">
              <template #rate>
                <strong>{{ formatPercent(responseRate) }}</strong>
              </template>
            </I18nT>
          </span>
        </li>
      </ul>
      <p class="mt-4 text-sm text-n-slate-11">
        {{ $t('CSAT_REPORTS.PLAIN_SUMMARY.HOW_TO_READ') }}
      </p>
    </section>
    <div
      class="flex sm:flex-row flex-col w-full gap-4 sm:gap-12 rounded-2xl border border-n-container/60 bg-n-solid-2/90 px-6 py-5 shadow-sm"
    >
      <CsatMetricCard
        :label="$t('CSAT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
        :tooltip="$t('CSAT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
        :value="responseCount"
        :is-loading="isLoading"
      />

      <div class="w-full sm:w-px bg-n-container/60" />

      <CsatMetricCard
        :label="$t('CSAT_REPORTS.METRIC.SATISFACTION_SCORE.LABEL')"
        :tooltip="$t('CSAT_REPORTS.METRIC.SATISFACTION_SCORE.TOOLTIP')"
        :value="formatPercent(satisfactionScore)"
        :is-loading="isLoading"
        :signal="csatSignal"
      />

      <div class="w-full sm:w-px bg-n-container/60" />

      <CsatMetricCard
        :label="$t('CSAT_REPORTS.METRIC.RESPONSE_RATE.LABEL')"
        :tooltip="$t('CSAT_REPORTS.METRIC.RESPONSE_RATE.TOOLTIP')"
        :value="formatPercent(responseRate)"
        :is-loading="isLoading"
      />
    </div>

    <CsatRatingDistribution
      :rating-percentage="ratingPercentage"
      :rating-count="ratingCount"
      :total-response-count="metrics.totalResponseCount"
      :is-loading="isLoading"
    />
  </div>
</template>
