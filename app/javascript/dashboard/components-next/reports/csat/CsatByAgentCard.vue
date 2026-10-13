<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import { formatPercent } from 'dashboard/helper/reportFormat';
import ReportCard from 'dashboard/components-next/reports/ui/ReportCard.vue';
import ReportBarList from 'dashboard/components-next/reports/ui/ReportBarList.vue';

// CSAT por agente em barras, com a linha da meta. Avisa quem usa (ranking de Agentes) quando
// as linhas chegam, para nao buscar duas vezes.
const props = defineProps({
  // { from, to, inboxId } em segundos unix
  filters: { type: Object, required: true },
});

const emit = defineEmits(['loaded']);

const CSAT_GOAL = 85;

const { t } = useI18n();
const rows = ref([]);

const shortName = name => {
  const [first, last] = (name || '').split(' ');
  return last ? `${first} ${last[0]}.` : first || '';
};

const tone = value => {
  if (value >= CSAT_GOAL) return 'bg-n-teal-9';
  return value >= CSAT_GOAL - 10 ? 'bg-n-amber-9' : 'bg-n-ruby-9';
};

watch(
  () => props.filters,
  async ({ from, to, inboxId }) => {
    if (!from) return;
    try {
      const { data } = await ReportsAPI.getBreakdown({
        kind: 'csat_by_agent',
        from,
        to,
        inboxId,
      });
      rows.value = data;
    } catch {
      rows.value = [];
    }
    emit('loaded', rows.value);
  },
  { immediate: true, deep: true }
);

const bars = computed(() =>
  rows.value.map(row => ({
    key: row.id,
    label: shortName(row.name),
    hint: `${row.name} · ${row.total}`,
    value: row.value,
    display: formatPercent(row.value),
    barClass: tone(row.value),
  }))
);
</script>

<template>
  <ReportCard
    :title="t('REPORTS_UI.AGENTS.CSAT_TITLE')"
    :subtitle="t('REPORTS_UI.AGENTS.CSAT_SUB')"
  >
    <ReportBarList
      :rows="bars"
      :max="100"
      :goal="CSAT_GOAL"
      :empty-text="t('REPORTS_UI.AGENTS.CSAT_EMPTY')"
    />
    <p v-if="bars.length" class="mt-3 mb-0 text-xs text-n-slate-10">
      {{ t('REPORTS_UI.AGENTS.CSAT_GOAL', { goal: formatPercent(CSAT_GOAL) }) }}
    </p>
  </ReportCard>
</template>
