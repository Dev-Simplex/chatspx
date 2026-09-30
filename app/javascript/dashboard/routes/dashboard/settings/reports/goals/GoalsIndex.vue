<script setup>
// CHAT-177: Relatórios → Metas. O servidor decide o que cada papel recebe; a tela só mostra o que veio.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import PerformanceGoalsAPI from 'dashboard/api/performanceGoals';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import GoalsMetricCell from './GoalsMetricCell.vue';
import GoalsEditor from './GoalsEditor.vue';

const METRICS = [
  'resolved_conversations',
  'first_response_time',
  'nps',
  'kanban_wins',
];

const { t, locale } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const accountId = useMapGetter('getCurrentAccountId');

const toKey = date =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
const now = new Date();
const currentMonth = toKey(now);

const month = ref(currentMonth);
const scope = ref('users');
const teamId = ref('');
const data = ref(null);
const teams = ref([]);
const loading = ref(false);
const failed = ref(false);
const editing = ref(false);

const monthLabel = key => {
  const [year, m] = key.split('-').map(Number);
  return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    month: 'long',
    year: 'numeric',
  }).format(new Date(year, m - 1, 1));
};

// Abre no mês atual e volta até 11 meses.
const monthOptions = computed(() =>
  Array.from({ length: 12 }, (_, i) =>
    toKey(new Date(now.getFullYear(), now.getMonth() - i, 1))
  )
);

const METRIC_LABELS = () => ({
  resolved_conversations: t(
    'PERFORMANCE_GOALS.METRICS.RESOLVED_CONVERSATIONS'
  ),
  first_response_time: t('PERFORMANCE_GOALS.METRICS.FIRST_RESPONSE_TIME'),
  nps: t('PERFORMANCE_GOALS.METRICS.NPS'),
  kanban_wins: t('PERFORMANCE_GOALS.METRICS.KANBAN_WINS'),
});
const metricLabel = metric => METRIC_LABELS()[metric];

const canManage = computed(() => !!data.value?.can_manage);
const canDefine = computed(() => canManage.value && month.value >= currentMonth);
const rows = computed(() => data.value?.rows || []);
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

const overallLabel = value =>
  value == null ? t('PERFORMANCE_GOALS.NO_DATA') : `${Math.round(value * 100)}%`;

const podiumClass = position =>
  ({
    1: 'bg-n-amber-3 text-n-amber-11',
    2: 'bg-n-slate-3 text-n-slate-11',
    3: 'bg-n-ruby-3 text-n-ruby-11',
  })[position] || 'text-n-slate-11';

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
  <div class="flex flex-col w-full gap-6 py-6">
    <GoalsEditor
      v-if="editing"
      :month="month >= currentMonth ? month : currentMonth"
      @close="editing = false"
      @saved="onSaved"
    />

    <template v-else>
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ $t('PERFORMANCE_GOALS.TITLE') }}
          </h1>
          <p class="mt-1 mb-0 text-sm text-n-slate-11">
            {{ $t('PERFORMANCE_GOALS.DESCRIPTION') }}
          </p>
        </div>
        <Button
          v-if="canDefine"
          :label="$t('PERFORMANCE_GOALS.DEFINE')"
          icon="i-lucide-target"
          size="sm"
          @click="editing = true"
        />
      </header>

      <div class="flex flex-wrap items-center gap-3">
        <select
          v-model="month"
          :aria-label="$t('PERFORMANCE_GOALS.MONTH')"
          class="reset-base h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option v-for="key in monthOptions" :key="key" :value="key">
            {{ monthLabel(key) }}
          </option>
        </select>
        <div class="inline-flex p-0.5 border rounded-lg border-n-weak bg-n-solid-1">
          <button
            v-for="option in ['users', 'teams']"
            :key="option"
            type="button"
            class="h-8 px-3 text-sm rounded-md"
            :class="
              scope === option
                ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
                : 'text-n-slate-11'
            "
            @click="scope = option"
          >
            {{
              option === 'users'
                ? $t('PERFORMANCE_GOALS.PEOPLE')
                : $t('PERFORMANCE_GOALS.TEAMS')
            }}
          </button>
        </div>
        <select
          v-if="scope === 'users' && canManage && teams.length"
          v-model="teamId"
          class="reset-base h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option value="">{{ $t('PERFORMANCE_GOALS.ALL_TEAMS') }}</option>
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
      </div>

      <p class="-mt-3 mb-0 text-xs text-n-slate-10">
        {{ $t('PERFORMANCE_GOALS.CRITERIA_HELP') }}
      </p>

      <p v-if="loading" class="text-sm text-n-slate-11">
        <span class="i-lucide-loader-circle size-4 animate-spin" />
      </p>
      <p v-else-if="failed" class="text-sm text-n-ruby-11">
        {{ $t('PERFORMANCE_GOALS.ERROR') }}
      </p>

      <template v-else>
        <section
          v-if="me"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between gap-3 mb-4">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ $t('PERFORMANCE_GOALS.MY_PERFORMANCE') }}
            </h2>
            <span class="text-sm font-semibold text-n-slate-12">
              {{ $t('PERFORMANCE_GOALS.OVERALL') }}:
              {{ overallLabel(me.overall) }}
            </span>
          </div>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div v-for="metric in METRICS" :key="metric">
              <p class="mb-1 text-xs text-n-slate-11">
                {{ metricLabel(metric) }}
              </p>
              <GoalsMetricCell :metric="metric" :data="me.metrics[metric]" />
            </div>
          </div>
        </section>

        <div v-if="isEmpty" class="py-10 text-center">
          <p class="text-sm text-n-slate-11">
            {{ $t('PERFORMANCE_GOALS.EMPTY') }}
          </p>
          <Button
            v-if="canDefine"
            class="mt-3"
            :label="$t('PERFORMANCE_GOALS.DEFINE')"
            size="sm"
            @click="editing = true"
          />
        </div>

        <div
          v-if="rows.length"
          class="overflow-x-auto border rounded-xl border-n-weak bg-n-solid-1"
        >
          <table class="w-full text-sm">
            <thead>
              <tr class="text-xs text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-2 font-medium">
                  {{ $t('PERFORMANCE_GOALS.POSITION') }}
                </th>
                <th class="px-3 py-2 font-medium">
                  {{ $t('PERFORMANCE_GOALS.NAME') }}
                </th>
                <th class="px-3 py-2 font-medium">
                  {{ $t('PERFORMANCE_GOALS.OVERALL') }}
                </th>
                <th
                  v-for="metric in METRICS"
                  :key="metric"
                  class="px-3 py-2 font-medium"
                >
                  {{ metricLabel(metric) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in rows"
                :key="row.id"
                class="border-b last:border-b-0 border-n-weak"
                :class="{ 'bg-n-alpha-1': isMine(row) }"
              >
                <td class="px-3 py-3">
                  <span
                    class="inline-flex items-center justify-center rounded-full size-7 text-xs font-semibold"
                    :class="podiumClass(row.position)"
                  >
                    {{ row.position }}
                  </span>
                </td>
                <td class="px-3 py-3">
                  <div class="flex items-center gap-2 min-w-[9rem]">
                    <Avatar
                      :name="row.name"
                      :src="row.avatar_url || ''"
                      :size="24"
                      rounded-full
                    />
                    <span class="font-medium text-n-slate-12">
                      {{ row.name }}
                    </span>
                    <span v-if="isMine(row)" class="text-xs text-n-slate-10">
                      {{ `(${$t('PERFORMANCE_GOALS.YOU')})` }}
                    </span>
                  </div>
                </td>
                <td class="px-3 py-3 font-semibold text-n-slate-12">
                  {{ overallLabel(row.overall) }}
                </td>
                <td v-for="metric in METRICS" :key="metric" class="px-3 py-3">
                  <p
                    v-if="metric === 'kanban_wins' && !kanbanConfigured"
                    class="mb-0 text-xs text-n-slate-10"
                  >
                    {{ $t('PERFORMANCE_GOALS.NO_DATA') }}
                  </p>
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
        </div>

        <p
          v-if="canManage && !kanbanConfigured"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ $t('PERFORMANCE_GOALS.KANBAN_NOT_CONFIGURED') }}
          <router-link
            :to="{ name: 'kanban_index', params: { accountId } }"
            class="underline text-n-blue-11"
          >
            {{ $t('PERFORMANCE_GOALS.KANBAN_LINK') }}
          </router-link>
        </p>
        <p v-else-if="canManage" class="mb-0 text-xs text-n-slate-10">
          {{ $t('PERFORMANCE_GOALS.KANBAN_LIMITATION') }}
        </p>

        <section v-if="canManage && withoutGoal.length">
          <h2 class="mb-2 text-sm font-semibold text-n-slate-12">
            {{ $t('PERFORMANCE_GOALS.WITHOUT_GOAL') }}
          </h2>
          <div class="flex flex-wrap gap-2">
            <span
              v-for="row in withoutGoal"
              :key="row.id"
              class="inline-flex items-center gap-2 px-2 py-1 text-sm border rounded-lg border-n-weak text-n-slate-11"
            >
              <Avatar
                :name="row.name"
                :src="row.avatar_url || ''"
                :size="20"
                rounded-full
              />
              {{ row.name }}
            </span>
          </div>
        </section>
      </template>
    </template>
  </div>
</template>
