<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import subDays from 'date-fns/subDays';
import startOfDay from 'date-fns/startOfDay';
import isSameDay from 'date-fns/isSameDay';
import format from 'date-fns/format';
import parseISO from 'date-fns/parseISO';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';

// Periodo dos relatorios no desenho do prototipo: Hoje / 7 dias / 30 dias em pilula e um
// "Personalizado" com duas datas. Mesma interface do calendario antigo (WootDatePicker):
// v-model:date-range, v-model:range-type e o evento dateRangeChanged([inicio, fim, tipo]).
const emit = defineEmits(['dateRangeChanged']);

const dateRange = defineModel('dateRange', { type: Array, default: undefined });
const rangeType = defineModel('rangeType', {
  type: String,
  default: undefined,
});

const { t } = useI18n();

const PRESETS = [
  { key: 'TODAY', days: 1, type: DATE_RANGE_TYPES.CUSTOM_RANGE },
  { key: 'LAST_7', days: 7, type: DATE_RANGE_TYPES.LAST_7_DAYS },
  { key: 'LAST_30', days: 30, type: DATE_RANGE_TYPES.LAST_30_DAYS },
];

const showCustom = ref(false);
const popover = ref(null);
onClickOutside(popover, () => {
  showCustom.value = false;
});

const today = () => startOfDay(new Date());
const presetRange = days => [subDays(today(), days - 1), today()];

// Qual pilula acende: a que tem exatamente as datas escolhidas; senao, Personalizado.
const activeKey = computed(() => {
  const [start, end] = dateRange.value || presetRange(7);
  const preset = PRESETS.find(item => {
    const [presetStart, presetEnd] = presetRange(item.days);
    return isSameDay(start, presetStart) && isSameDay(end, presetEnd);
  });
  return preset ? preset.key : 'CUSTOM';
});

const apply = (start, end, type) => {
  dateRange.value = [start, end];
  rangeType.value = type;
  emit('dateRangeChanged', [start, end, type]);
};

const choose = preset => {
  showCustom.value = false;
  const [start, end] = presetRange(preset.days);
  apply(start, end, preset.type);
};

const iso = date => (date ? format(date, 'yyyy-MM-dd') : '');
const customFrom = ref('');
const customTo = ref('');
const maxDate = iso(new Date());

const openCustom = () => {
  const [start, end] = dateRange.value || presetRange(7);
  customFrom.value = iso(start);
  customTo.value = iso(end);
  showCustom.value = !showCustom.value;
};

const canApply = computed(
  () => customFrom.value && customTo.value && customFrom.value <= customTo.value
);

const applyCustom = () => {
  if (!canApply.value) return;
  showCustom.value = false;
  apply(
    parseISO(customFrom.value),
    parseISO(customTo.value),
    DATE_RANGE_TYPES.CUSTOM_RANGE
  );
};

const customLabel = computed(() => {
  if (activeKey.value !== 'CUSTOM' || !dateRange.value) {
    return t('REPORTS_UI.PERIOD.CUSTOM');
  }
  const [start, end] = dateRange.value;
  return `${format(start, 'dd/MM')} – ${format(end, 'dd/MM')}`;
});
</script>

<template>
  <!-- O alvo #report-scope-filters recebe a caixa "Filtros" (ReportScopeFilters) da tela, para ela
       ficar sempre ao lado do periodo, qualquer que seja a barra que embrulha os dois. -->
  <div class="flex flex-wrap items-center gap-2">
    <div ref="popover" class="relative">
      <div
        class="inline-flex items-center gap-0.5 p-1 rounded-full border border-n-weak bg-n-alpha-1"
        role="radiogroup"
        :aria-label="t('REPORTS_UI.PERIOD.LABEL')"
      >
        <button
          v-for="preset in PRESETS"
          :key="preset.key"
          type="button"
          role="radio"
          :aria-checked="activeKey === preset.key"
          class="h-8 px-3.5 m-0 text-[13px] font-semibold rounded-full whitespace-nowrap"
          :class="
            activeKey === preset.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="choose(preset)"
        >
          {{ t(`REPORTS_UI.PERIOD.${preset.key}`) }}
        </button>
        <button
          type="button"
          role="radio"
          :aria-checked="activeKey === 'CUSTOM'"
          class="flex items-center gap-1 h-8 px-3.5 m-0 text-[13px] font-semibold rounded-full whitespace-nowrap tabular-nums"
          :class="
            activeKey === 'CUSTOM'
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="openCustom"
        >
          <span class="i-lucide-calendar-range size-3.5" />
          {{ customLabel }}
        </button>
      </div>

      <div
        v-if="showCustom"
        class="absolute left-0 z-50 flex flex-col gap-3 p-4 mt-2 rounded-[18px] border border-n-weak bg-n-solid-2 shadow-xl w-72 top-full"
      >
        <label
          class="flex flex-col gap-1 m-0 text-xs font-semibold text-n-slate-11"
        >
          {{ t('REPORTS_UI.PERIOD.FROM') }}
          <input
            v-model="customFrom"
            type="date"
            :max="customTo || maxDate"
            class="h-9 px-2 m-0 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label
          class="flex flex-col gap-1 m-0 text-xs font-semibold text-n-slate-11"
        >
          {{ t('REPORTS_UI.PERIOD.TO') }}
          <input
            v-model="customTo"
            type="date"
            :min="customFrom"
            :max="maxDate"
            class="h-9 px-2 m-0 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <button
          type="button"
          class="h-9 m-0 text-sm font-semibold text-white rounded-full bg-n-brand disabled:opacity-50"
          :disabled="!canApply"
          @click="applyCustom"
        >
          {{ t('REPORTS_UI.PERIOD.APPLY') }}
        </button>
      </div>
    </div>
    <div id="report-scope-filters" class="empty:hidden" />
  </div>
</template>
