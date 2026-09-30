<script setup>
// CHAT-177: definir metas do mês (atual ou o próximo). Campo vazio = sem meta. O servidor só devolve
// os atendentes/times que quem abre pode gerenciar, e grava o lote inteiro numa transação.
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PerformanceGoalsAPI from 'dashboard/api/performanceGoals';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import ReportHeader from '../components/ReportHeader.vue';
import { METRICS, monthKey, monthLabel } from './goalsFormat';

const props = defineProps({
  month: { type: String, required: true },
});
const emit = defineEmits(['close', 'saved']);

const VISIBILITIES = ['managers', 'own', 'everyone'];

const { t, locale } = useI18n();

const now = new Date();
const monthValues = [
  monthKey(now),
  monthKey(new Date(now.getFullYear(), now.getMonth() + 1, 1)),
];
const monthOptions = computed(() =>
  monthValues.map(value => ({ value, label: monthLabel(value, locale.value) }))
);

const editMonth = ref(
  monthValues.includes(props.month) ? props.month : monthValues[0]
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

const tabs = computed(() => [
  { label: t('PERFORMANCE_GOALS.PEOPLE'), value: 'users' },
  { label: t('PERFORMANCE_GOALS.TEAMS'), value: 'teams' },
]);
const teamOptions = computed(() => [
  { value: '', label: t('PERFORMANCE_GOALS.ALL_TEAMS') },
  ...(data.value?.teams || []).map(team => ({
    value: String(team.id),
    label: team.name,
  })),
]);

const METRIC_LABELS = () => ({
  resolved_conversations: t(
    'PERFORMANCE_GOALS.METRICS.RESOLVED_CONVERSATIONS'
  ),
  first_response_time: t('PERFORMANCE_GOALS.METRICS.FIRST_RESPONSE_TIME'),
  nps: t('PERFORMANCE_GOALS.METRICS.NPS'),
  kanban_wins: t('PERFORMANCE_GOALS.METRICS.KANBAN_WINS'),
});
// Unidade ao lado do campo, para ninguém digitar segundos no lugar de minutos.
const UNITS = () => ({
  first_response_time: t('PERFORMANCE_GOALS.UNITS.MIN'),
  nps: t('PERFORMANCE_GOALS.UNITS.PTS'),
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
    ? t('PERFORMANCE_GOALS.EDITOR.SINCE', {
        month: monthLabel(since, locale.value),
      })
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
  const { data: payload } = await PerformanceGoalsAPI.getGoals(
    editMonth.value
  );
  data.value = payload;
  visibility.value = payload.visibility;
  fillValues(payload);
};

// "Aplicar a todos do time": copia a linha de cima para as linhas visíveis.
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
        const value = String(
          values[key(type, target.id, metric)] ?? ''
        ).trim();
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
    errorMessage.value =
      body.error || t('PERFORMANCE_GOALS.EDITOR.SAVE_ERROR');
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

const inputClass =
  'reset-base !w-24 h-9 px-2.5 text-sm tabular-nums text-right border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12 outline-none focus:border-n-brand focus:ring-2 focus:ring-n-brand/20';

watch(editMonth, load);
onMounted(load);
</script>

<template>
  <div class="flex flex-col">
    <ReportHeader
      :header-title="$t('PERFORMANCE_GOALS.EDITOR.TITLE')"
      :header-description="`${$t('PERFORMANCE_GOALS.EDITOR.MONTH_HINT')} ${$t('PERFORMANCE_GOALS.EDITOR.EMPTY_HINT')}`"
    >
      <Button
        :label="$t('PERFORMANCE_GOALS.EDITOR.BACK')"
        icon="i-lucide-arrow-left"
        variant="faded"
        color="slate"
        size="sm"
        @click="emit('close')"
      />
    </ReportHeader>

    <div class="flex flex-wrap items-center gap-3 mb-4">
      <div class="w-48">
        <Select v-model="editMonth" :options="monthOptions" />
      </div>
      <div v-if="tab === 'users' && data?.teams?.length" class="w-48">
        <Select v-model="teamId" :options="teamOptions" />
      </div>
      <div class="ltr:ml-auto rtl:mr-auto">
        <TabBar
          :tabs="tabs"
          :initial-active-tab="tab === 'users' ? 0 : 1"
          @tab-changed="item => (tab = item.value)"
        />
      </div>
    </div>

    <section
      v-if="data"
      class="overflow-x-auto border rounded-xl border-n-weak bg-n-solid-1"
    >
      <table class="w-full text-sm">
        <thead>
          <tr
            class="text-xs font-medium tracking-wider text-left uppercase border-b text-n-slate-10 border-n-weak"
          >
            <th class="py-3 ltr:pl-5 rtl:pr-5">
              {{ tab === 'users' ? $t('PERFORMANCE_GOALS.NAME') : $t('PERFORMANCE_GOALS.MEMBERS') }}
            </th>
            <th v-for="metric in METRICS" :key="metric" class="px-3 py-3">
              {{ METRIC_LABELS()[metric] }}
            </th>
          </tr>
          <tr class="border-b border-n-weak bg-n-alpha-1">
            <td class="py-3 ltr:pl-5 rtl:pr-5">
              <Button
                :label="$t('PERFORMANCE_GOALS.EDITOR.APPLY_ALL')"
                :title="$t('PERFORMANCE_GOALS.EDITOR.APPLY_HINT')"
                icon="i-lucide-copy-check"
                size="xs"
                variant="faded"
                color="slate"
                @click="applyToVisible"
              />
            </td>
            <td v-for="metric in METRICS" :key="metric" class="px-3 py-3">
              <div class="flex items-center gap-1.5">
                <input
                  v-model="bulk[metric]"
                  type="number"
                  min="0"
                  step="any"
                  :class="inputClass"
                />
                <span class="text-xs text-n-slate-10">
                  {{ UNITS()[metric] }}
                </span>
              </div>
            </td>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="target in targets"
            :key="target.id"
            class="border-b last:border-b-0 border-n-weak"
            :class="{ 'bg-n-ruby-2': errorKey === `${typeOf()}:${target.id}` }"
          >
            <td class="py-3 ltr:pl-5 rtl:pr-5">
              <div class="flex items-center gap-3 min-w-[10rem]">
                <Avatar
                  :name="target.name"
                  :src="target.avatar_url || ''"
                  :size="28"
                  rounded-full
                />
                <span class="font-medium text-n-slate-12">
                  {{ target.name }}
                </span>
              </div>
            </td>
            <td
              v-for="metric in METRICS"
              :key="metric"
              class="px-3 py-3 align-top"
            >
              <div class="flex items-center gap-1.5">
                <input
                  v-model="values[key(typeOf(), target.id, metric)]"
                  type="number"
                  min="0"
                  step="any"
                  :class="inputClass"
                />
                <span class="text-xs text-n-slate-10">
                  {{ UNITS()[metric] }}
                </span>
              </div>
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
    </section>

    <section v-if="data?.can_change_visibility" class="mt-8">
      <h2 class="mb-3 text-base font-semibold text-n-slate-12">
        {{ $t('PERFORMANCE_GOALS.VISIBILITY.TITLE') }}
      </h2>
      <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
        <RadioCard
          v-for="option in VISIBILITIES"
          :id="option"
          :key="option"
          :label="VISIBILITY_TEXT()[option][0]"
          :description="VISIBILITY_TEXT()[option][1]"
          :is-active="visibility === option"
          @select="changeVisibility"
        />
      </div>
    </section>

    <div
      class="sticky bottom-0 flex items-center justify-end gap-3 py-4 mt-6 border-t border-n-weak bg-n-surface-1"
    >
      <p v-if="errorMessage" class="mb-0 text-sm text-n-ruby-11 ltr:mr-auto rtl:ml-auto">
        {{ errorMessage }}
      </p>
      <Button
        :label="$t('PERFORMANCE_GOALS.EDITOR.BACK')"
        variant="faded"
        color="slate"
        @click="emit('close')"
      />
      <Button
        :label="$t('PERFORMANCE_GOALS.EDITOR.SAVE')"
        :is-loading="saving"
        @click="save"
      />
    </div>
  </div>
</template>
