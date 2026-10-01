<script setup>
// CHAT-177: "Como funciona" da tela de Metas — a conta da nota, os indicadores, os selos e o ritmo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { TONES } from './goalsFormat';

defineEmits(['close']);

const { t } = useI18n();

const metrics = computed(() => [
  {
    label: t('PERFORMANCE_GOALS.METRICS.RESOLVED_CONVERSATIONS'),
    body: t('PERFORMANCE_GOALS.HELP.RESOLVED'),
  },
  {
    label: t('PERFORMANCE_GOALS.METRICS.FIRST_RESPONSE_TIME'),
    body: t('PERFORMANCE_GOALS.HELP.FRT'),
  },
  {
    label: t('PERFORMANCE_GOALS.METRICS.NPS'),
    body: t('PERFORMANCE_GOALS.HELP.NPS'),
  },
  {
    label: t('PERFORMANCE_GOALS.METRICS.KANBAN_WINS'),
    body: t('PERFORMANCE_GOALS.HELP.KANBAN'),
  },
]);

const statuses = computed(() => [
  {
    tone: TONES.hit,
    label: t('PERFORMANCE_GOALS.STATUS.HIT'),
    body: t('PERFORMANCE_GOALS.HELP.HIT'),
  },
  {
    tone: TONES.onPace,
    label: t('PERFORMANCE_GOALS.STATUS.ON_PACE'),
    body: t('PERFORMANCE_GOALS.HELP.ON_PACE'),
  },
  {
    tone: TONES.near,
    label: t('PERFORMANCE_GOALS.STATUS.NEAR'),
    body: t('PERFORMANCE_GOALS.HELP.NEAR'),
  },
  {
    tone: TONES.behind,
    label: t('PERFORMANCE_GOALS.STATUS.BEHIND'),
    body: t('PERFORMANCE_GOALS.HELP.BEHIND'),
  },
  {
    tone: TONES.below,
    label: t('PERFORMANCE_GOALS.STATUS.BELOW'),
    body: t('PERFORMANCE_GOALS.HELP.BELOW'),
  },
  {
    tone: TONES.start,
    label: t('PERFORMANCE_GOALS.STATUS.START'),
    body: t('PERFORMANCE_GOALS.HELP.START'),
  },
]);
</script>

<template>
  <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex items-center justify-between gap-3 mb-4">
      <h2
        class="flex items-center gap-2 mb-0 text-base font-semibold text-n-slate-12"
      >
        <span class="i-lucide-circle-help size-5 text-n-slate-10" />
        {{ $t('PERFORMANCE_GOALS.HELP.TITLE') }}
      </h2>
      <Button
        :label="$t('PERFORMANCE_GOALS.HELP.CLOSE')"
        icon="i-lucide-x"
        size="sm"
        variant="ghost"
        color="slate"
        @click="$emit('close')"
      />
    </div>

    <div class="grid grid-cols-1 gap-6 text-sm lg:grid-cols-2">
      <div>
        <h3 class="mb-1 text-sm font-semibold text-n-slate-12">
          {{ $t('PERFORMANCE_GOALS.HELP.OVERALL_TITLE') }}
        </h3>
        <p class="mb-2 text-n-slate-11">
          {{ $t('PERFORMANCE_GOALS.HELP.OVERALL_BODY') }}
        </p>
        <p class="mb-0 text-n-slate-11">
          {{ $t('PERFORMANCE_GOALS.HELP.RANKING') }}
        </p>
      </div>

      <div>
        <h3 class="mb-1 text-sm font-semibold text-n-slate-12">
          {{ $t('PERFORMANCE_GOALS.HELP.METRICS_TITLE') }}
        </h3>
        <ul class="flex flex-col gap-1.5 mb-0 list-none ltr:pl-0 rtl:pr-0">
          <li v-for="item in metrics" :key="item.label" class="text-n-slate-11">
            <span class="font-medium text-n-slate-12">{{ item.label }}:</span>
            {{ item.body }}
          </li>
        </ul>
      </div>

      <div>
        <h3 class="mb-2 text-sm font-semibold text-n-slate-12">
          {{ $t('PERFORMANCE_GOALS.HELP.STATUS_TITLE') }}
        </h3>
        <ul class="flex flex-col gap-2 mb-0 list-none ltr:pl-0 rtl:pr-0">
          <li
            v-for="item in statuses"
            :key="item.label"
            class="flex items-start gap-2 text-n-slate-11"
          >
            <span
              class="flex-shrink-0 px-2 py-0.5 text-[11px] font-medium rounded-full whitespace-nowrap"
              :class="item.tone.pill"
            >
              {{ item.label }}
            </span>
            <span>{{ item.body }}</span>
          </li>
        </ul>
      </div>

      <div>
        <h3 class="mb-1 text-sm font-semibold text-n-slate-12">
          {{ $t('PERFORMANCE_GOALS.HELP.PACE_TITLE') }}
        </h3>
        <div
          class="relative h-1.5 my-3 overflow-hidden rounded-full bg-n-alpha-2"
        >
          <div
            class="absolute inset-y-0 rounded-full ltr:left-0 rtl:right-0 bg-n-slate-6 w-[65%]"
          />
          <div class="relative h-full rounded-full bg-n-amber-9 w-[50%]" />
        </div>
        <p class="mb-2 text-n-slate-11">
          {{ $t('PERFORMANCE_GOALS.HELP.PACE_BODY') }}
        </p>
        <p class="mb-0 text-n-slate-11">
          {{ $t('PERFORMANCE_GOALS.HELP.PROJECTION_BODY') }}
        </p>
      </div>
    </div>
  </section>
</template>
