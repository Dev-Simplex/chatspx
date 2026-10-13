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
      class="relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] p-5"
    >
      <h3
        class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
      >
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
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <CsatMetricCard
        icon="i-lucide-messages-square"
        :label="$t('CSAT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
        :tooltip="$t('CSAT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
        :value="responseCount"
        :is-loading="isLoading"
      />

      <CsatMetricCard
        icon="i-lucide-smile"
        :label="$t('CSAT_REPORTS.METRIC.SATISFACTION_SCORE.LABEL')"
        :tooltip="$t('CSAT_REPORTS.METRIC.SATISFACTION_SCORE.TOOLTIP')"
        :value="formatPercent(satisfactionScore)"
        :is-loading="isLoading"
        :signal="csatSignal"
      />

      <CsatMetricCard
        icon="i-lucide-send"
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
