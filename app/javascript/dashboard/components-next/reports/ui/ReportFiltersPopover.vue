<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

// Botao "Filtros" do prototipo: uma janela com Caixa, Time e Atendente lado a lado, cada opcao com
// quantas conversas chegaram no periodo. Uma opcao por grupo (o backend dos relatorios recorta por
// um id de cada vez): marcar outra troca a anterior, marcar a mesma desmarca.
const props = defineProps({
  // quais grupos a tela aceita: 'inbox' | 'team' | 'agent'
  groups: { type: Array, default: () => ['inbox'] },
  // { since, until } em segundos unix, para as contagens
  period: { type: Object, default: () => ({}) },
});

// { inbox: id|null, team: id|null, agent: id|null }
const selection = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const open = ref(false);
const root = ref(null);
const counts = ref({ inbox: {}, team: {}, agent: {} });
onClickOutside(root, () => {
  open.value = false;
});

const GROUPS = {
  inbox: {
    icon: 'i-lucide-inbox',
    label: 'REPORTS_UI.FILTERS.INBOX',
    api: 'getInboxReports',
  },
  team: {
    icon: 'i-lucide-users',
    label: 'REPORTS_UI.FILTERS.TEAM',
    api: 'getTeamReports',
  },
  agent: {
    icon: 'i-lucide-user-round',
    label: 'REPORTS_UI.FILTERS.AGENT',
    api: 'getAgentReports',
  },
};

const loadCounts = async () => {
  const { since, until } = props.period;
  if (!since) return;
  const entries = await Promise.all(
    props.groups.map(async group => {
      try {
        const { data } = await SummaryReportsAPI[GROUPS[group].api]({
          since,
          until,
        });
        return [
          group,
          Object.fromEntries(
            data.map(row => [row.id, row.conversations_count])
          ),
        ];
      } catch {
        return [group, {}];
      }
    })
  );
  counts.value = { ...counts.value, ...Object.fromEntries(entries) };
};

const toggleOpen = () => {
  open.value = !open.value;
  if (open.value) {
    if (props.groups.includes('inbox')) store.dispatch('inboxes/get');
    if (props.groups.includes('team')) store.dispatch('teams/get');
    if (props.groups.includes('agent')) store.dispatch('agents/get');
    loadCounts();
  }
};
watch(
  () => props.period,
  () => open.value && loadCounts(),
  { deep: true }
);

const optionsOf = group => {
  const source =
    { inbox: inboxes, team: teams, agent: agents }[group].value || [];
  // quem mais recebeu conversas no periodo primeiro, como no prototipo
  return source
    .map(item => ({
      id: item.id,
      name: item.name || item.title,
      count: counts.value[group]?.[item.id] ?? null,
    }))
    .sort((a, b) => (b.count || 0) - (a.count || 0));
};

const toggle = (group, id) => {
  selection.value = {
    ...selection.value,
    [group]: selection.value?.[group] === id ? null : id,
  };
};

const activeCount = computed(
  () => props.groups.filter(group => selection.value?.[group]).length
);

const clear = () => {
  selection.value = Object.fromEntries(
    props.groups.map(group => [group, null])
  );
};
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="flex items-center gap-1.5 h-9 px-3.5 m-0 text-[13px] font-semibold rounded-full border border-n-weak bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2"
      :aria-expanded="open"
      @click="toggleOpen"
    >
      <span class="i-lucide-sliders-horizontal size-4" />
      {{ t('REPORTS_UI.FILTERS.BUTTON') }}
      <span
        v-if="activeCount"
        class="grid min-w-[18px] h-[18px] px-1 place-items-center rounded-full bg-n-brand text-[11px] font-bold text-white"
      >
        {{ activeCount }}
      </span>
    </button>

    <div
      v-if="open"
      class="absolute left-0 z-50 flex flex-col mt-2 overflow-hidden rounded-[22px] border border-n-weak bg-n-solid-2 shadow-2xl top-full w-[min(36rem,calc(100vw-2rem))]"
    >
      <div class="flex items-center justify-between px-5 pt-4 pb-2">
        <span class="text-[15px] font-extrabold text-n-slate-12">
          {{ t('REPORTS_UI.FILTERS.TITLE') }}
        </span>
        <button
          type="button"
          class="grid p-0 m-0 rounded-full size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('REPORTS_UI.FILTERS.CLOSE')"
          @click="open = false"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
      <div
        class="grid gap-x-6 gap-y-5 px-5 pb-4 overflow-y-auto max-h-[22rem]"
        :class="groups.length > 1 ? 'sm:grid-cols-2' : ''"
      >
        <section v-for="group in groups" :key="group" class="min-w-0">
          <p
            class="flex items-center gap-1.5 m-0 mb-2 text-[11px] font-bold tracking-wider uppercase text-n-slate-11"
          >
            <span class="size-3.5" :class="GROUPS[group].icon" />
            {{ t(GROUPS[group].label) }}
          </p>
          <p
            v-if="!optionsOf(group).length"
            class="m-0 text-sm text-n-slate-10"
          >
            {{ t('REPORTS_UI.FILTERS.EMPTY') }}
          </p>
          <label
            v-for="option in optionsOf(group)"
            :key="option.id"
            class="flex items-center gap-3 py-1.5 m-0 text-sm cursor-pointer text-n-slate-12"
          >
            <input
              type="checkbox"
              class="m-0 rounded size-4 accent-n-brand"
              :checked="selection?.[group] === option.id"
              @change="toggle(group, option.id)"
            />
            <span class="truncate grow">{{ option.name }}</span>
            <span
              v-if="option.count !== null"
              class="text-xs tabular-nums text-n-slate-10"
            >
              {{ option.count }}
            </span>
          </label>
        </section>
      </div>
      <div
        class="flex flex-wrap items-center justify-between gap-2 px-5 py-3 border-t border-n-weak"
      >
        <button
          type="button"
          class="h-8 px-3 m-0 text-sm font-semibold rounded-full text-n-slate-12 hover:bg-n-alpha-2"
          @click="clear"
        >
          {{ t('REPORTS_UI.FILTERS.CLEAR') }}
        </button>
        <span class="text-xs text-n-slate-10">
          {{ t('REPORTS_UI.FILTERS.HINT') }}
        </span>
      </div>
    </div>
  </div>
</template>
