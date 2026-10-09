<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import NpsReportsAPI from 'dashboard/api/npsReports';
import ReportsAPI from 'dashboard/api/reports';
import { formatPercent } from 'dashboard/helper/reportFormat';
import ReportCard from 'dashboard/components-next/reports/ui/ReportCard.vue';
import ReportBarList from 'dashboard/components-next/reports/ui/ReportBarList.vue';

// Topo da tela de NPS no desenho do painel: a nota grande com a barra de promotores/neutros/
// detratores e as notas de 0 a 10; ao lado, os comentarios recentes e o NPS de cada time.
const props = defineProps({
  // o mesmo requestPayload da tela: { from, to, user_ids, inbox_id, team_id }
  filters: { type: Object, required: true },
});

const MAX_COMMENTS = 5;
const NPS_GOAL = 50;

const { t } = useI18n();
const metrics = useMapGetter('npsResponses/getMetrics');

const comments = ref([]);
const commentFilter = ref('all');
const byTeam = ref([]);

const band = score => {
  if (score >= 9) return 'promoter';
  return score >= 7 ? 'passive' : 'detractor';
};
const BAND_CLASS = {
  promoter: 'bg-n-teal-9',
  passive: 'bg-n-amber-9',
  detractor: 'bg-n-ruby-9',
};
const BAND_TEXT = {
  promoter: 'text-n-teal-11 bg-n-teal-3',
  passive: 'text-n-amber-11 bg-n-amber-3',
  detractor: 'text-n-ruby-11 bg-n-ruby-3',
};

const load = async () => {
  const { from, to } = props.filters;
  if (!from) return;
  const [list, teams] = await Promise.all([
    NpsReportsAPI.get({
      ...props.filters,
      page: 1,
      response_state: 'responded',
    }).catch(() => ({ data: [] })),
    ReportsAPI.getBreakdown({
      kind: 'nps_by_team',
      from,
      to,
      inboxId: props.filters.inbox_id,
    }).catch(() => ({ data: [] })),
  ]);
  const rows = Array.isArray(list.data) ? list.data : list.data.payload || [];
  comments.value = rows.filter(row => row.comment);
  byTeam.value = teams.data;
};

watch(() => props.filters, load, { immediate: true, deep: true });

const answered = computed(() => (metrics.value?.total_count || 0) > 0);
const delta = computed(() => metrics.value?.nps_delta);

const bands = computed(() => [
  {
    key: 'promoter',
    label: t('REPORTS_UI.NPS.PROMOTERS'),
    hint: t('REPORTS_UI.NPS.PROMOTERS_HINT'),
    pct: metrics.value?.promoters_pct || 0,
  },
  {
    key: 'passive',
    label: t('REPORTS_UI.NPS.PASSIVES'),
    hint: t('REPORTS_UI.NPS.PASSIVES_HINT'),
    pct: metrics.value?.passives_pct || 0,
  },
  {
    key: 'detractor',
    label: t('REPORTS_UI.NPS.DETRACTORS'),
    hint: t('REPORTS_UI.NPS.DETRACTORS_HINT'),
    pct: metrics.value?.detractors_pct || 0,
  },
]);

const scores = computed(() => {
  const counts = metrics.value?.scores_count || {};
  return Array.from({ length: 11 }, (_, score) => ({
    score,
    count: Number(counts[score] || 0),
  }));
});
const maxScore = computed(() =>
  Math.max(1, ...scores.value.map(item => item.count))
);

const visibleComments = computed(() =>
  comments.value
    .filter(
      row =>
        commentFilter.value === 'all' || band(row.score) === commentFilter.value
    )
    .slice(0, MAX_COMMENTS)
);

const teamTone = value => {
  if (value >= NPS_GOAL) return 'bg-n-teal-9';
  return value >= 0 ? 'bg-n-amber-9' : 'bg-n-ruby-9';
};

const teamBars = computed(() =>
  byTeam.value.map(row => ({
    key: row.id,
    label: row.name,
    hint: t('REPORTS_UI.NPS.RESPONSES', { n: row.total }, row.total),
    // escala de -100 a 100 deslocada para 0..200, para a barra comecar do zero
    value: row.value + 100,
    display: String(row.value),
    barClass: teamTone(row.value),
  }))
);

const FILTERS = ['all', 'promoter', 'detractor'];
const filterLabel = key =>
  ({
    all: t('REPORTS_UI.NPS.ALL'),
    promoter: t('REPORTS_UI.NPS.PROMOTERS'),
    detractor: t('REPORTS_UI.NPS.DETRACTORS'),
  })[key];
</script>

<template>
  <div class="grid grid-cols-1 gap-4 lg:grid-cols-12">
    <ReportCard
      class="lg:col-span-5"
      :title="t('REPORTS_UI.NPS.TITLE')"
      :subtitle="
        t(
          'REPORTS_UI.NPS.SUB',
          { n: metrics?.total_count || 0 },
          metrics?.total_count || 0
        )
      "
    >
      <p v-if="!answered" class="mt-4 mb-0 text-sm text-n-slate-11">
        {{ t('REPORTS_UI.NPS.EMPTY') }}
      </p>
      <template v-else>
        <div class="flex items-end gap-3 mt-3">
          <span
            class="text-[56px] font-extrabold leading-[0.95] tracking-[-0.045em] tabular-nums text-n-slate-12"
          >
            {{ metrics.nps_score }}
          </span>
          <span
            v-if="delta"
            class="px-2 py-0.5 mb-2 text-xs font-bold rounded-full"
            :class="
              delta > 0
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-ruby-3 text-n-ruby-11'
            "
          >
            {{
              delta > 0
                ? t('REPORTS_UI.NPS.DELTA_UP', { n: delta })
                : t('REPORTS_UI.NPS.DELTA_DOWN', { n: -delta })
            }}
          </span>
        </div>
        <div
          class="flex h-3 gap-0.5 mt-4 overflow-hidden rounded-full bg-n-alpha-2"
        >
          <span
            v-for="item in bands"
            :key="item.key"
            class="block h-full first:rounded-l-full last:rounded-r-full"
            :class="BAND_CLASS[item.key]"
            :style="{ width: `${item.pct}%` }"
          />
        </div>
        <div class="grid grid-cols-3 gap-2 mt-3">
          <div v-for="item in bands" :key="item.key" class="min-w-0">
            <span
              class="flex items-center gap-1.5 text-xs font-semibold text-n-slate-11"
            >
              <span class="rounded-full size-2" :class="BAND_CLASS[item.key]" />
              {{ item.label }}
            </span>
            <span
              class="block text-lg font-extrabold tabular-nums text-n-slate-12"
            >
              {{ formatPercent(item.pct) }}
            </span>
            <span class="block text-[11px] text-n-slate-10">
              {{ item.hint }}
            </span>
          </div>
        </div>
        <div class="h-px my-4 bg-n-weak" />
        <p
          class="m-0 text-xs font-bold tracking-wider uppercase text-n-slate-11"
        >
          {{ t('REPORTS_UI.NPS.SCORES') }}
        </p>
        <div class="grid items-end h-32 grid-cols-11 gap-1.5 mt-3">
          <div
            v-for="item in scores"
            :key="item.score"
            class="flex flex-col items-center justify-end h-full gap-1"
          >
            <span class="text-[11px] font-bold tabular-nums text-n-slate-12">
              {{ item.count }}
            </span>
            <span
              class="block w-full max-w-[26px] rounded-t-md rounded-b-sm"
              :class="BAND_CLASS[band(item.score)]"
              :style="{
                height: `${Math.max((item.count / maxScore) * 70, 3)}%`,
              }"
            />
            <span class="text-[11px] text-n-slate-10">{{ item.score }}</span>
          </div>
        </div>
      </template>
    </ReportCard>

    <div class="flex flex-col gap-4 lg:col-span-7">
      <ReportCard
        :title="t('REPORTS_UI.NPS.COMMENTS_TITLE')"
        :subtitle="t('REPORTS_UI.NPS.COMMENTS_SUB')"
      >
        <template #actions>
          <div
            class="inline-flex gap-0.5 p-0.5 rounded-full border border-n-weak bg-n-alpha-1"
            role="radiogroup"
          >
            <button
              v-for="key in FILTERS"
              :key="key"
              type="button"
              role="radio"
              :aria-checked="commentFilter === key"
              class="h-7 px-3 m-0 text-xs font-semibold rounded-full"
              :class="
                commentFilter === key
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
              "
              @click="commentFilter = key"
            >
              {{ filterLabel(key) }}
            </button>
          </div>
        </template>
        <p
          v-if="!visibleComments.length"
          class="mt-4 mb-0 text-sm text-n-slate-11"
        >
          {{ t('REPORTS_UI.NPS.COMMENTS_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col p-0 m-0 mt-3 list-none">
          <li
            v-for="row in visibleComments"
            :key="row.id"
            class="flex items-center gap-3 px-2 py-2.5 -mx-2 rounded-xl hover:bg-n-alpha-1"
          >
            <span
              class="grid min-w-[30px] h-7 px-1.5 place-items-center rounded-full text-[13px] font-extrabold tabular-nums"
              :class="BAND_TEXT[band(row.score)]"
            >
              {{ row.score }}
            </span>
            <span class="flex flex-col min-w-0 grow">
              <span class="text-sm font-semibold text-n-slate-12 truncate">
                {{ t('REPORTS_UI.NPS.QUOTE', { text: row.comment }) }}
              </span>
              <span class="text-xs text-n-slate-10 truncate">
                {{ row.contact?.name }}
                <template v-if="row.assigned_agent?.name">
                  · {{ row.assigned_agent.name }}
                </template>
              </span>
            </span>
          </li>
        </ul>
      </ReportCard>

      <ReportCard
        :title="t('REPORTS_UI.NPS.BY_TEAM_TITLE')"
        :subtitle="t('REPORTS_UI.NPS.BY_TEAM_SUB')"
      >
        <ReportBarList
          :rows="teamBars"
          :max="200"
          :goal="NPS_GOAL + 100"
          :empty-text="t('REPORTS_UI.NPS.BY_TEAM_EMPTY')"
        />
      </ReportCard>
    </div>
  </div>
</template>
