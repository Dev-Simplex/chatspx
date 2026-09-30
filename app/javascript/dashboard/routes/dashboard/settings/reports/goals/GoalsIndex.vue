<script setup>
// CHAT-177: Relatórios → Metas. O servidor decide o que cada papel recebe; a tela só mostra o que veio.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import PerformanceGoalsAPI from 'dashboard/api/performanceGoals';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ReportHeader from '../components/ReportHeader.vue';
import GoalsMetricCell from './GoalsMetricCell.vue';
import GoalsEditor from './GoalsEditor.vue';
import {
  METRICS,
  goalTone,
  formatMetric,
  percentLabel,
  monthKey,
  monthLabel,
} from './goalsFormat';

const { t, locale } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const accountId = useMapGetter('getCurrentAccountId');

const now = new Date();
const currentMonth = monthKey(now);

const month = ref(currentMonth);
const scope = ref('users');
const teamId = ref('');
const data = ref(null);
const teams = ref([]);
const loading = ref(false);
const failed = ref(false);
const errorMessage = ref('');
const editing = ref(false);

// Abre no mês atual e volta até 11 meses.
const monthOptions = computed(() =>
  Array.from({ length: 12 }, (_, i) => {
    const key = monthKey(new Date(now.getFullYear(), now.getMonth() - i, 1));
    return { value: key, label: monthLabel(key, locale.value) };
  })
);
const teamOptions = computed(() => [
  { value: '', label: t('PERFORMANCE_GOALS.ALL_TEAMS') },
  ...teams.value.map(team => ({ value: String(team.id), label: team.name })),
]);
const scopeTabs = computed(() => [
  { label: t('PERFORMANCE_GOALS.PEOPLE'), value: 'users' },
  { label: t('PERFORMANCE_GOALS.TEAMS'), value: 'teams' },
]);

const METRIC_LABELS = () => ({
  resolved_conversations: t(
    'PERFORMANCE_GOALS.METRICS.RESOLVED_CONVERSATIONS'
  ),
  first_response_time: t('PERFORMANCE_GOALS.METRICS.FIRST_RESPONSE_TIME'),
  nps: t('PERFORMANCE_GOALS.METRICS.NPS'),
  kanban_wins: t('PERFORMANCE_GOALS.METRICS.KANBAN_WINS'),
});
const metricLabel = metric => METRIC_LABELS()[metric];
// Mapa explícito: chave dinâmica de i18n some do bundle no build.
const STATUS_LABELS = () => ({
  HIT: t('PERFORMANCE_GOALS.STATUS.HIT'),
  NEAR: t('PERFORMANCE_GOALS.STATUS.NEAR'),
  BELOW: t('PERFORMANCE_GOALS.STATUS.BELOW'),
});
const statusLabel = attainment => STATUS_LABELS()[goalTone(attainment).key] || '';

const canManage = computed(() => !!data.value?.can_manage);
const canDefine = computed(() => canManage.value && month.value >= currentMonth);
const rows = computed(() => data.value?.rows || []);
const podium = computed(() =>
  rows.value.length >= 3 ? rows.value.slice(0, 3) : []
);
const withoutGoal = computed(() => data.value?.without_goal || []);
const me = computed(() => data.value?.me);
const kanbanConfigured = computed(() => data.value?.kanban_configured !== false);
const isEmpty = computed(
  () => !loading.value && !failed.value && !rows.value.length && !me.value
);

const isMine = row =>
  scope.value === 'users' && row.id === currentUser.value?.id;
// Números completos: quem gerencia sempre; o atendente só na própria linha.
const showNumbers = row => canManage.value || isMine(row);
const overall = value => percentLabel(value) || t('PERFORMANCE_GOALS.NO_DATA');

const MEDALS = {
  1: 'bg-[#f5c451]/20 text-[#b7791f] ring-[#f5c451]/60',
  2: 'bg-n-slate-4 text-n-slate-11 ring-n-slate-7',
  3: 'bg-[#cd7f32]/15 text-[#a0612a] ring-[#cd7f32]/50',
};

const meNumbers = metric => {
  const { actual, goal } = me.value.metrics[metric];
  if (actual == null) return '';
  const fmt = value => formatMetric(metric, value, locale.value);
  return goal == null
    ? fmt(actual)
    : t('PERFORMANCE_GOALS.OF', { actual: fmt(actual), goal: fmt(goal) });
};

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data: payload } = await PerformanceGoalsAPI.getRanking({
      month: month.value,
      scope: scope.value,
      teamId: scope.value === 'users' ? teamId.value : '',
    });
    data.value = payload;
    if (payload.can_manage && !teams.value.length) {
      const { data: goals } = await PerformanceGoalsAPI.getGoals(month.value);
      teams.value = goals.teams;
    }
  } catch (error) {
    failed.value = true;
    // 403: o servidor diz que não há acesso; o resto é erro de carga.
    errorMessage.value =
      error?.response?.status === 403
        ? error.response.data?.error
        : t('PERFORMANCE_GOALS.ERROR');
    data.value = null;
  } finally {
    loading.value = false;
  }
};

const onSaved = () => {
  editing.value = false;
  load();
};

watch([month, scope, teamId], load);
onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full pb-12">
    <GoalsEditor
      v-if="editing"
      :month="month >= currentMonth ? month : currentMonth"
      @close="editing = false"
      @saved="onSaved"
    />

    <template v-else>
      <ReportHeader
        :header-title="$t('PERFORMANCE_GOALS.TITLE')"
        :header-description="$t('PERFORMANCE_GOALS.DESCRIPTION')"
      >
        <Button
          v-if="canDefine"
          :label="$t('PERFORMANCE_GOALS.DEFINE')"
          icon="i-lucide-target"
          size="sm"
          @click="editing = true"
        />
      </ReportHeader>

      <div class="flex flex-wrap items-center gap-3 mb-2">
        <div class="w-48">
          <Select v-model="month" :options="monthOptions" />
        </div>
        <div v-if="scope === 'users' && canManage && teams.length" class="w-48">
          <Select v-model="teamId" :options="teamOptions" />
        </div>
        <div class="ltr:ml-auto rtl:mr-auto">
          <TabBar
            :tabs="scopeTabs"
            :initial-active-tab="scope === 'users' ? 0 : 1"
            @tab-changed="tab => (scope = tab.value)"
          />
        </div>
      </div>
      <p class="mb-6 text-xs text-n-slate-10">
        {{ $t('PERFORMANCE_GOALS.CRITERIA_HELP') }}
      </p>

      <div
        v-if="loading"
        class="flex items-center justify-center py-20 text-n-slate-10"
      >
        <span class="i-lucide-loader-circle size-6 animate-spin" />
      </div>

      <div
        v-else-if="failed"
        class="flex flex-col items-center gap-3 py-16 text-center border rounded-xl border-n-weak bg-n-solid-1"
      >
        <span class="i-lucide-lock size-8 text-n-slate-9" />
        <p class="mb-0 text-sm text-n-slate-11">{{ errorMessage }}</p>
      </div>

      <div v-else class="flex flex-col gap-6">
        <!-- Meu desempenho -->
        <section
          v-if="me"
          class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center justify-between gap-3 mb-5">
            <div class="flex items-center gap-3">
              <Avatar
                :name="me.name"
                :src="me.avatar_url || ''"
                :size="40"
                rounded-full
              />
              <div>
                <h2 class="mb-0 text-base font-semibold text-n-slate-12">
                  {{ $t('PERFORMANCE_GOALS.MY_PERFORMANCE') }}
                </h2>
                <p
                  v-if="me.position && rows.length"
                  class="mb-0 text-xs text-n-slate-11"
                >
                  {{
                    $t('PERFORMANCE_GOALS.RANK_POSITION', {
                      position: me.position,
                    })
                  }}
                </p>
              </div>
            </div>
            <div class="text-right">
              <p
                class="mb-0 text-xs font-medium tracking-wider uppercase text-n-slate-10"
              >
                {{ $t('PERFORMANCE_GOALS.OVERALL') }}
              </p>
              <p
                class="mb-0 text-3xl font-semibold tabular-nums"
                :class="goalTone(me.overall).text"
              >
                {{ overall(me.overall) }}
              </p>
            </div>
          </div>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <div
              v-for="metric in METRICS"
              :key="metric"
              class="p-4 rounded-lg bg-n-alpha-1"
            >
              <p
                class="mb-2 text-xs font-medium tracking-wider uppercase text-n-slate-10"
              >
                {{ metricLabel(metric) }}
              </p>
              <template v-if="me.metrics[metric].attainment != null">
                <div class="flex items-baseline justify-between gap-2">
                  <span
                    class="text-2xl font-semibold tabular-nums"
                    :class="goalTone(me.metrics[metric].attainment).text"
                  >
                    {{ percentLabel(me.metrics[metric].attainment) }}
                  </span>
                  <span
                    class="px-2 py-0.5 text-[11px] font-medium rounded-full"
                    :class="goalTone(me.metrics[metric].attainment).pill"
                  >
                    {{ statusLabel(me.metrics[metric].attainment) }}
                  </span>
                </div>
                <GoalsMetricCell
                  class="mt-1 [&>span]:hidden"
                  :metric="metric"
                  :data="me.metrics[metric]"
                />
              </template>
              <template v-else>
                <p class="mb-0 text-2xl font-semibold text-n-slate-8">
                  {{ $t('PERFORMANCE_GOALS.HIDDEN') }}
                </p>
                <p class="mt-1 mb-0 text-xs text-n-slate-11">
                  {{
                    me.metrics[metric].goal == null
                      ? $t('PERFORMANCE_GOALS.NO_GOAL')
                      : $t('PERFORMANCE_GOALS.NO_DATA')
                  }}
                  <template v-if="meNumbers(metric)">
                    {{ `· ${meNumbers(metric)}` }}
                  </template>
                </p>
              </template>
            </div>
          </div>
        </section>

        <!-- Vazio -->
        <div
          v-if="isEmpty"
          class="flex flex-col items-center gap-3 py-16 text-center border border-dashed rounded-xl border-n-weak"
        >
          <span class="i-lucide-target size-8 text-n-slate-9" />
          <p class="mb-0 text-sm text-n-slate-11">
            {{ $t('PERFORMANCE_GOALS.EMPTY') }}
          </p>
          <Button
            v-if="canDefine"
            :label="$t('PERFORMANCE_GOALS.DEFINE')"
            size="sm"
            @click="editing = true"
          />
        </div>

        <!-- Pódio -->
        <section v-if="podium.length" class="grid grid-cols-1 gap-3 md:grid-cols-3">
          <div
            v-for="row in podium"
            :key="row.id"
            class="relative flex items-center gap-4 p-4 border rounded-xl bg-n-solid-1"
            :class="isMine(row) ? 'border-n-brand' : 'border-n-weak'"
          >
            <span
              class="absolute flex items-center justify-center text-xs font-bold rounded-full top-3 ltr:right-3 rtl:left-3 size-7 ring-1"
              :class="MEDALS[row.position]"
            >
              {{ row.position }}
            </span>
            <Avatar
              :name="row.name"
              :src="row.avatar_url || ''"
              :size="48"
              rounded-full
            />
            <div class="min-w-0">
              <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
                {{ row.name }}
              </p>
              <p
                class="mb-0 text-2xl font-semibold tabular-nums"
                :class="goalTone(row.overall).text"
              >
                {{ overall(row.overall) }}
              </p>
              <p class="mb-0 text-xs text-n-slate-10">
                {{ $t('PERFORMANCE_GOALS.OVERALL') }}
              </p>
            </div>
          </div>
        </section>

        <!-- Ranking -->
        <section
          v-if="rows.length"
          class="overflow-x-auto border rounded-xl border-n-weak bg-n-solid-1"
        >
          <table class="w-full text-sm">
            <thead>
              <tr
                class="text-xs font-medium tracking-wider text-left uppercase border-b text-n-slate-10 border-n-weak"
              >
                <th class="py-3 ltr:pl-5 rtl:pr-5 w-12">
                  {{ $t('PERFORMANCE_GOALS.POSITION') }}
                </th>
                <th class="px-3 py-3">{{ $t('PERFORMANCE_GOALS.NAME') }}</th>
                <th class="px-3 py-3">{{ $t('PERFORMANCE_GOALS.OVERALL') }}</th>
                <th
                  v-for="metric in METRICS"
                  :key="metric"
                  class="px-3 py-3 font-medium"
                >
                  {{ metricLabel(metric) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in rows"
                :key="row.id"
                class="border-b last:border-b-0 border-n-weak hover:bg-n-alpha-1"
                :class="{ 'bg-n-alpha-1': isMine(row) }"
              >
                <td
                  class="py-4 ltr:pl-5 rtl:pr-5 tabular-nums text-n-slate-11"
                  :class="{
                    'ltr:shadow-[inset_3px_0_0_0] rtl:shadow-[inset_-3px_0_0_0] shadow-n-brand':
                      isMine(row),
                  }"
                >
                  {{ row.position }}
                </td>
                <td class="px-3 py-4">
                  <div class="flex items-center gap-3 min-w-[10rem]">
                    <Avatar
                      :name="row.name"
                      :src="row.avatar_url || ''"
                      :size="32"
                      rounded-full
                    />
                    <div class="min-w-0">
                      <p class="mb-0 font-medium truncate text-n-slate-12">
                        {{ row.name }}
                      </p>
                      <p v-if="isMine(row)" class="mb-0 text-xs text-n-brand">
                        {{ $t('PERFORMANCE_GOALS.YOU') }}
                      </p>
                    </div>
                  </div>
                </td>
                <td class="px-3 py-4">
                  <span
                    class="text-base font-semibold tabular-nums"
                    :class="goalTone(row.overall).text"
                  >
                    {{ overall(row.overall) }}
                  </span>
                </td>
                <td v-for="metric in METRICS" :key="metric" class="px-3 py-4">
                  <span
                    v-if="metric === 'kanban_wins' && !kanbanConfigured"
                    class="text-xs text-n-slate-10"
                  >
                    {{ $t('PERFORMANCE_GOALS.NO_DATA') }}
                  </span>
                  <GoalsMetricCell
                    v-else
                    :metric="metric"
                    :data="row.metrics[metric]"
                    :show-numbers="showNumbers(row)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <div
          v-if="canManage && rows.length"
          class="flex items-start gap-2 text-xs text-n-slate-11"
        >
          <span class="i-lucide-info size-4 flex-shrink-0 mt-px" />
          <span v-if="!kanbanConfigured">
            {{ $t('PERFORMANCE_GOALS.KANBAN_NOT_CONFIGURED') }}
            <router-link
              :to="{ name: 'kanban_index', params: { accountId } }"
              class="underline text-n-blue-11"
            >
              {{ $t('PERFORMANCE_GOALS.KANBAN_LINK') }}
            </router-link>
          </span>
          <span v-else>{{ $t('PERFORMANCE_GOALS.KANBAN_LIMITATION') }}</span>
        </div>

        <!-- Sem meta definida -->
        <section
          v-if="canManage && withoutGoal.length"
          class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <h2
            class="mb-3 text-xs font-medium tracking-wider uppercase text-n-slate-10"
          >
            {{ $t('PERFORMANCE_GOALS.WITHOUT_GOAL') }}
            <span class="ltr:ml-1 rtl:mr-1 tabular-nums">
              {{ `(${withoutGoal.length})` }}
            </span>
          </h2>
          <div class="flex flex-wrap gap-2">
            <span
              v-for="row in withoutGoal"
              :key="row.id"
              class="inline-flex items-center gap-2 py-1 text-sm rounded-full ltr:pl-1 ltr:pr-3 rtl:pr-1 rtl:pl-3 bg-n-alpha-1 text-n-slate-11"
            >
              <Avatar
                :name="row.name"
                :src="row.avatar_url || ''"
                :size="22"
                rounded-full
              />
              {{ row.name }}
            </span>
          </div>
        </section>
      </div>
    </template>
  </div>
</template>
