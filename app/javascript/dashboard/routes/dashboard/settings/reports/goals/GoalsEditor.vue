<script setup>
// CHAT-177: definir metas do mês (atual ou o próximo). Campo vazio = sem meta. O servidor só devolve
// os atendentes/times que quem abre pode gerenciar, e grava o lote inteiro numa transação.
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PerformanceGoalsAPI from 'dashboard/api/performanceGoals';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  month: { type: String, required: true },
});
const emit = defineEmits(['close', 'saved']);

const METRICS = [
  'resolved_conversations',
  'first_response_time',
  'nps',
  'kanban_wins',
];
const VISIBILITIES = ['managers', 'own', 'everyone'];

const { t, locale } = useI18n();

const toKey = date =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
const now = new Date();
const monthOptions = [
  toKey(now),
  toKey(new Date(now.getFullYear(), now.getMonth() + 1, 1)),
];

const editMonth = ref(
  monthOptions.includes(props.month) ? props.month : monthOptions[0]
);
const tab = ref('users');
const teamId = ref('');
const data = ref(null);
const values = reactive({});
const bulk = reactive({});
const saving = ref(false);
const errorMessage = ref('');
const errorKey = ref('');
const visibility = ref('managers');

const monthLabel = key => {
  const [year, m] = key.split('-').map(Number);
  return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    month: 'long',
    year: 'numeric',
  }).format(new Date(year, m - 1, 1));
};

const METRIC_LABELS = () => ({
  resolved_conversations: t(
    'PERFORMANCE_GOALS.METRICS.RESOLVED_CONVERSATIONS'
  ),
  first_response_time: t('PERFORMANCE_GOALS.METRICS.FIRST_RESPONSE_TIME'),
  nps: t('PERFORMANCE_GOALS.METRICS.NPS'),
  kanban_wins: t('PERFORMANCE_GOALS.METRICS.KANBAN_WINS'),
});
const VISIBILITY_TEXT = () => ({
  managers: [
    t('PERFORMANCE_GOALS.VISIBILITY.MANAGERS'),
    t('PERFORMANCE_GOALS.VISIBILITY.MANAGERS_HINT'),
  ],
  own: [
    t('PERFORMANCE_GOALS.VISIBILITY.OWN'),
    t('PERFORMANCE_GOALS.VISIBILITY.OWN_HINT'),
  ],
  everyone: [
    t('PERFORMANCE_GOALS.VISIBILITY.EVERYONE'),
    t('PERFORMANCE_GOALS.VISIBILITY.EVERYONE_HINT'),
  ],
});

const key = (type, id, metric) => `${type}:${id}:${metric}`;
const typeOf = () => (tab.value === 'users' ? 'user' : 'team');

const targets = computed(() => {
  if (!data.value) return [];
  if (tab.value === 'teams') return data.value.teams;
  if (!teamId.value) return data.value.users;
  return data.value.users.filter(user =>
    user.team_ids.includes(Number(teamId.value))
  );
});

const sinceLabel = (target, metric) => {
  const since = target.goals[metric]?.since_month;
  return since && since < editMonth.value
    ? t('PERFORMANCE_GOALS.EDITOR.SINCE', { month: monthLabel(since) })
    : '';
};

const fillValues = payload => {
  Object.keys(values).forEach(k => delete values[k]);
  [
    ['user', payload.users],
    ['team', payload.teams],
  ].forEach(([type, list]) =>
    list.forEach(target =>
      METRICS.forEach(metric => {
        const goal = target.goals[metric];
        values[key(type, target.id, metric)] =
          goal?.value == null ? '' : String(goal.value);
      })
    )
  );
};

const load = async () => {
  errorMessage.value = '';
  const { data: payload } = await PerformanceGoalsAPI.getGoals(editMonth.value);
  data.value = payload;
  visibility.value = payload.visibility;
  fillValues(payload);
};

// "Aplicar a todos do time": copia a linha do cabeçalho para as linhas visíveis.
const applyToVisible = () => {
  targets.value.forEach(target =>
    METRICS.forEach(metric => {
      if (String(bulk[metric] ?? '').trim() !== '') {
        values[key(typeOf(), target.id, metric)] = String(bulk[metric]);
      }
    })
  );
};

const save = async () => {
  saving.value = true;
  errorMessage.value = '';
  errorKey.value = '';
  const goals = [];
  [
    ['user', data.value.users],
    ['team', data.value.teams],
  ].forEach(([type, list]) =>
    list.forEach(target =>
      METRICS.forEach(metric => {
        const value = String(values[key(type, target.id, metric)] ?? '').trim();
        goals.push({
          target_type: type,
          target_id: target.id,
          metric,
          value: value === '' ? null : value.replace(',', '.'),
        });
      })
    )
  );
  try {
    await PerformanceGoalsAPI.saveGoals({ month: editMonth.value, goals });
    useAlert(t('PERFORMANCE_GOALS.EDITOR.SAVED'));
    emit('saved');
  } catch (error) {
    const body = error?.response?.data || {};
    errorMessage.value = body.error || t('PERFORMANCE_GOALS.EDITOR.SAVE_ERROR');
    if (body.target_type) {
      errorKey.value = `${body.target_type}:${body.target_id}`;
    }
  } finally {
    saving.value = false;
  }
};

const changeVisibility = async value => {
  await PerformanceGoalsAPI.updateVisibility(value);
  visibility.value = value;
  useAlert(t('PERFORMANCE_GOALS.VISIBILITY.SAVED'));
};

watch(editMonth, load);
onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-5">
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ $t('PERFORMANCE_GOALS.EDITOR.TITLE') }}
        </h1>
        <p class="mt-1 mb-0 text-sm text-n-slate-11">
          {{ $t('PERFORMANCE_GOALS.EDITOR.MONTH_HINT') }}
          {{ $t('PERFORMANCE_GOALS.EDITOR.EMPTY_HINT') }}
        </p>
      </div>
      <Button
        :label="$t('PERFORMANCE_GOALS.EDITOR.BACK')"
        icon="i-lucide-arrow-left"
        variant="faded"
        color="slate"
        size="sm"
        @click="emit('close')"
      />
    </header>

    <div class="flex flex-wrap items-center gap-3">
      <select
        v-model="editMonth"
        class="reset-base h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        <option v-for="option in monthOptions" :key="option" :value="option">
          {{ monthLabel(option) }}
        </option>
      </select>
      <div class="inline-flex p-0.5 border rounded-lg border-n-weak bg-n-solid-1">
        <button
          v-for="option in ['users', 'teams']"
          :key="option"
          type="button"
          class="h-8 px-3 text-sm rounded-md"
          :class="
            tab === option
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11'
          "
          @click="tab = option"
        >
          {{
            option === 'users'
              ? $t('PERFORMANCE_GOALS.PEOPLE')
              : $t('PERFORMANCE_GOALS.TEAMS')
          }}
        </button>
      </div>
      <select
        v-if="tab === 'users' && data?.teams?.length"
        v-model="teamId"
        class="reset-base h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        <option value="">{{ $t('PERFORMANCE_GOALS.ALL_TEAMS') }}</option>
        <option v-for="team in data.teams" :key="team.id" :value="team.id">
          {{ team.name }}
        </option>
      </select>
    </div>

    <div
      v-if="data"
      class="overflow-x-auto border rounded-xl border-n-weak bg-n-solid-1"
    >
      <table class="w-full text-sm">
        <thead>
          <tr class="text-xs text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ $t('PERFORMANCE_GOALS.NAME') }}
            </th>
            <th
              v-for="metric in METRICS"
              :key="metric"
              class="px-3 py-2 font-medium"
            >
              {{ METRIC_LABELS()[metric] }}
            </th>
          </tr>
          <tr class="border-b border-n-weak bg-n-alpha-1">
            <td class="px-3 py-2">
              <Button
                :label="$t('PERFORMANCE_GOALS.EDITOR.APPLY_ALL')"
                :title="$t('PERFORMANCE_GOALS.EDITOR.APPLY_HINT')"
                size="xs"
                variant="faded"
                color="slate"
                @click="applyToVisible"
              />
            </td>
            <td v-for="metric in METRICS" :key="metric" class="px-3 py-2">
              <input
                v-model="bulk[metric]"
                type="number"
                min="0"
                step="any"
                class="reset-base w-24 h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
              />
            </td>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="target in targets"
            :key="target.id"
            class="border-b last:border-b-0 border-n-weak"
            :class="{
              'bg-n-ruby-2': errorKey === `${typeOf()}:${target.id}`,
            }"
          >
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ target.name }}
            </td>
            <td v-for="metric in METRICS" :key="metric" class="px-3 py-2">
              <input
                v-model="values[key(typeOf(), target.id, metric)]"
                type="number"
                min="0"
                step="any"
                class="reset-base w-24 h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
              />
              <p
                v-if="sinceLabel(target, metric)"
                class="mt-1 mb-0 text-[11px] text-n-slate-10"
              >
                {{ sinceLabel(target, metric) }}
              </p>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-if="errorMessage" class="mb-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>
    <div>
      <Button
        :label="$t('PERFORMANCE_GOALS.EDITOR.SAVE')"
        :is-loading="saving"
        @click="save"
      />
    </div>

    <section
      v-if="data?.can_change_visibility"
      class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <h2 class="mb-3 text-base font-semibold text-n-slate-12">
        {{ $t('PERFORMANCE_GOALS.VISIBILITY.TITLE') }}
      </h2>
      <label
        v-for="option in VISIBILITIES"
        :key="option"
        class="flex items-start gap-3 py-2 cursor-pointer"
      >
        <input
          type="radio"
          name="goals-visibility"
          class="mt-1"
          :checked="visibility === option"
          @change="changeVisibility(option)"
        />
        <span>
          <span class="block text-sm font-medium text-n-slate-12">
            {{ VISIBILITY_TEXT()[option][0] }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ VISIBILITY_TEXT()[option][1] }}
          </span>
        </span>
      </label>
    </section>
  </section>
</template>
