<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ReportsAPI from 'dashboard/api/reports';
import { formatPercent } from 'dashboard/helper/reportFormat';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ReportCard from 'dashboard/components-next/reports/ui/ReportCard.vue';
import ReportBarList from 'dashboard/components-next/reports/ui/ReportBarList.vue';

// Topo da tela de SLA no desenho do painel: o cumprimento grande com uma linha por politica;
// ao lado, as conversas que estouraram por ultimo e o cumprimento de cada time.
const props = defineProps({
  // o mesmo activeFilter da tela: { from, to, inbox_id, ... }
  filters: { type: Object, required: true },
});

const SLA_GOAL = 95;
const MAX_BREACHES = 5;

const { t } = useI18n();
const metrics = useMapGetter('slaReports/getMetrics');
const breaches = useMapGetter('slaReports/getAll');

const byPolicy = ref([]);
const byTeam = ref([]);

const tone = value => {
  if (value >= SLA_GOAL) return 'bg-n-teal-9';
  return value >= SLA_GOAL - 15 ? 'bg-n-amber-9' : 'bg-n-ruby-9';
};

const load = async () => {
  const { from, to, inbox_id: inboxId } = props.filters;
  if (!from) return;
  const fetch = kind =>
    ReportsAPI.getBreakdown({ kind, from, to, inboxId })
      .then(({ data }) => data)
      .catch(() => []);
  [byPolicy.value, byTeam.value] = await Promise.all([
    fetch('sla_by_policy'),
    fetch('sla_by_team'),
  ]);
};

watch(() => props.filters, load, { immediate: true, deep: true });

const total = computed(() => metrics.value?.numberOfConversations || 0);
const misses = computed(() => metrics.value?.numberOfSLAMisses || 0);
const hitRate = computed(() => parseFloat(metrics.value?.hitRate) || 0);

const teamBars = computed(() =>
  byTeam.value.map(row => ({
    key: row.id,
    label: row.name,
    hint: `${row.total - row.missed}/${row.total}`,
    value: row.value,
    display: formatPercent(row.value),
    barClass: tone(row.value),
  }))
);

const recentBreaches = computed(() =>
  (breaches.value || []).slice(0, MAX_BREACHES)
);
</script>

<template>
  <div class="grid grid-cols-1 gap-4 lg:grid-cols-12">
    <ReportCard
      class="lg:col-span-7"
      :title="t('REPORTS_UI.SLA.TITLE')"
      :subtitle="t('REPORTS_UI.SLA.SUB')"
    >
      <p v-if="!total" class="mt-4 mb-0 text-sm text-n-slate-11">
        {{ t('REPORTS_UI.SLA.EMPTY') }}
      </p>
      <template v-else>
        <div class="flex items-end gap-3 mt-3">
          <span
            class="text-[56px] font-extrabold leading-[0.95] tracking-[-0.045em] tabular-nums text-n-slate-12"
          >
            {{ formatPercent(hitRate) }}
          </span>
          <span class="mb-2 text-[13px] text-n-slate-11">
            {{
              t('REPORTS_UI.SLA.OF_TOTAL', {
                ok: total - misses,
                total,
              })
            }}
          </span>
        </div>
        <div
          class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)_4rem_4rem] gap-3 mt-5 pb-2 border-b border-n-weak text-[11px] font-bold tracking-wider uppercase text-n-slate-11"
        >
          <span>{{ t('REPORTS_UI.SLA.POLICY') }}</span>
          <span>{{ t('REPORTS_UI.SLA.MET') }}</span>
          <span />
          <span class="text-right">{{ t('REPORTS_UI.SLA.MISSED') }}</span>
        </div>
        <div
          v-for="row in byPolicy"
          :key="row.id"
          class="grid grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)_4rem_4rem] items-center gap-3 py-2.5 border-b border-n-weak last:border-b-0"
        >
          <span class="text-[13px] font-semibold text-n-slate-12 truncate">
            {{ row.name }}
          </span>
          <span class="h-2 overflow-hidden rounded-full bg-n-alpha-2">
            <span
              class="block h-full rounded-full"
              :class="tone(row.value)"
              :style="{ width: `${row.value}%` }"
            />
          </span>
          <span
            class="text-xs font-bold text-right tabular-nums text-n-slate-12"
          >
            {{ formatPercent(row.value) }}
          </span>
          <span
            class="text-xs font-bold text-right tabular-nums"
            :class="row.missed ? 'text-n-ruby-11' : 'text-n-slate-10'"
          >
            {{ row.missed }}
          </span>
        </div>
      </template>
    </ReportCard>

    <ReportCard
      class="lg:col-span-5"
      :title="t('REPORTS_UI.SLA.BREACHES_TITLE')"
      :subtitle="t('REPORTS_UI.SLA.BREACHES_SUB')"
    >
      <template #actions>
        <span
          v-if="misses"
          class="px-2 py-0.5 text-xs font-bold rounded-full bg-n-ruby-3 text-n-ruby-11"
        >
          {{ t('REPORTS_UI.SLA.BREACHES_COUNT', { n: misses }, misses) }}
        </span>
      </template>
      <p
        v-if="!recentBreaches.length"
        class="mt-4 mb-0 text-sm text-n-slate-11"
      >
        {{ t('REPORTS_UI.SLA.BREACHES_EMPTY') }}
      </p>
      <ul v-else class="flex flex-col p-0 m-0 mt-3 list-none">
        <li v-for="item in recentBreaches" :key="item.applied_sla.id">
          <router-link
            :to="{
              name: 'inbox_conversation',
              params: { conversation_id: item.conversation.id },
            }"
            class="flex items-center gap-3 px-2 py-2 -mx-2 no-underline rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
          >
            <span class="rounded-full size-2 shrink-0 bg-n-ruby-9" />
            <span class="flex flex-col min-w-0 grow">
              <span class="text-sm font-semibold truncate">
                #{{ item.conversation.id }} ·
                {{ item.conversation.contact?.name }}
              </span>
              <span class="text-xs text-n-slate-10 truncate">
                {{ item.applied_sla.sla_name }}
              </span>
            </span>
            <Avatar
              v-if="item.conversation.assignee"
              :name="item.conversation.assignee.name"
              :src="item.conversation.assignee.thumbnail"
              :size="24"
              rounded-full
            />
          </router-link>
        </li>
      </ul>
      <template v-if="teamBars.length">
        <div class="h-px my-4 bg-n-weak" />
        <p
          class="m-0 text-xs font-bold tracking-wider uppercase text-n-slate-11"
        >
          {{ t('REPORTS_UI.SLA.BY_TEAM') }}
        </p>
        <ReportBarList :rows="teamBars" :max="100" :goal="SLA_GOAL" />
      </template>
    </ReportCard>
  </div>
</template>
