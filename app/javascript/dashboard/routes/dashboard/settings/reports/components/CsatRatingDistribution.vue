<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatPercent } from 'dashboard/helper/reportFormat';
import { CSAT_RATINGS } from 'shared/constants/messages';

const props = defineProps({
  ratingPercentage: {
    type: Object,
    default: () => ({}),
  },
  ratingCount: {
    type: Object,
    default: () => ({}),
  },
  totalResponseCount: {
    type: Number,
    default: 0,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const sortedRatings = computed(() =>
  [...CSAT_RATINGS].sort((a, b) => b.value - a.value)
);

const getRatingLabel = value => {
  const rating = CSAT_RATINGS.find(r => r.value === value);
  // Nota + carinha e nome: "5 · 😍 Excelente" (so o nome nao dizia que nota era; a carinha ja vem na traducao).
  return rating ? `${value} · ${t(rating.translationKey)}` : '';
};

const getRatingCount = value => {
  return props.ratingCount[value] || 0;
};
</script>

<template>
  <div
    class="relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] px-6 py-5"
  >
    <span class="text-sm font-medium text-n-slate-11">
      {{ $t('CSAT_REPORTS.METRIC.RATING_DISTRIBUTION') }}
    </span>

    <div v-if="isLoading" class="mt-4">
      <div class="h-6 w-full rounded-full bg-n-slate-3 animate-pulse" />
      <div class="flex gap-6 mt-4">
        <div
          v-for="n in 5"
          :key="n"
          class="h-4 w-20 rounded bg-n-slate-3 animate-pulse"
        />
      </div>
    </div>

    <div v-else class="mt-4">
      <div
        v-if="totalResponseCount"
        class="flex h-6 w-full rounded-full overflow-hidden bg-n-alpha-2"
      >
        <div
          v-for="rating in sortedRatings"
          :key="rating.value"
          v-tooltip="
            `${getRatingLabel(rating.value)}: ${formatPercent(ratingPercentage[rating.value])} (${getRatingCount(rating.value)})`
          "
          :style="{
            width: `${ratingPercentage[rating.value]}%`,
            backgroundColor: rating.color,
          }"
          class="h-full transition-all duration-300 first:rounded-s-full last:rounded-e-full cursor-default"
        />
      </div>
      <div v-else class="h-6 w-full rounded-full bg-n-alpha-2" />

      <div class="flex flex-wrap gap-x-6 gap-y-2 mt-4">
        <div
          v-for="rating in sortedRatings"
          :key="rating.value"
          class="flex items-center gap-2"
        >
          <span class="text-sm text-n-slate-11">
            {{ getRatingLabel(rating.value) }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ formatPercent(ratingPercentage[rating.value]) }}
          </span>
          <span class="text-xs text-n-slate-10">
            ({{ getRatingCount(rating.value) }})
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
