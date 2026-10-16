<script setup>
import { computed, ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import subDays from 'date-fns/subDays';
import ReportPeriodPicker from 'dashboard/components-next/reports/ui/ReportPeriodPicker.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import {
  generateReportURLParams,
  parseReportURLParams,
} from '../helpers/reportFilterHelper';
import { readInboxScope, writeInboxScope } from '../helpers/inboxScope';
import InboxScopeFilter from './Filters/InboxScopeFilter.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';

const props = defineProps({
  disabled: {
    type: Boolean,
    default: false,
  },
  showInboxScope: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['filterChange']);

const route = useRoute();
const router = useRouter();

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const businessHoursSelected = ref(false);
const inboxScopeId = ref(null);
// periodo das contagens do botao Filtros
const countPeriod = computed(() => ({
  since: getUnixStartOfDay(customDateRange.value[0]),
  until: getUnixEndOfDay(customDateRange.value[1]),
}));

const updateURLParams = () => {
  const params = generateReportURLParams({
    from: getUnixStartOfDay(customDateRange.value[0]),
    to: getUnixEndOfDay(customDateRange.value[1]),
    businessHours: businessHoursSelected.value,
    range: selectedDateRange.value,
    inboxId: props.showInboxScope ? inboxScopeId.value : null,
  });

  router.replace({ query: { ...params } });
};

const emitChange = () => {
  updateURLParams();
  emit('filterChange', {
    from: getUnixStartOfDay(customDateRange.value[0]),
    to: getUnixEndOfDay(customDateRange.value[1]),
    businessHours: businessHoursSelected.value,
    inboxId: props.showInboxScope ? inboxScopeId.value : null,
  });
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  emitChange();
};

const onBusinessHoursToggle = () => {
  emitChange();
};

const onInboxScopeChange = value => {
  writeInboxScope(value);
  emitChange();
};

const initializeFromURL = () => {
  const urlParams = parseReportURLParams(route.query);

  // Set the range type first
  if (urlParams.range) {
    selectedDateRange.value = urlParams.range;
  }

  // Restore dates from URL if available
  if (urlParams.from && urlParams.to) {
    customDateRange.value = [
      new Date(urlParams.from * 1000),
      new Date(urlParams.to * 1000),
    ];
  }

  if (urlParams.businessHours) {
    businessHoursSelected.value = urlParams.businessHours;
  }

  inboxScopeId.value = urlParams.inboxId || readInboxScope();
};

onMounted(() => {
  initializeFromURL();
  emitChange();
});
</script>

<template>
  <div
    class="flex flex-col justify-between gap-3 md:flex-row items-center"
    :class="{ 'pointer-events-none opacity-50': disabled }"
  >
    <div class="flex flex-col flex-wrap items-start gap-2 md:flex-row">
      <ReportPeriodPicker
        v-model:date-range="customDateRange"
        v-model:range-type="selectedDateRange"
        @date-range-changed="onDateRangeChange"
      />
      <InboxScopeFilter
        v-if="showInboxScope"
        v-model="inboxScopeId"
        :period="countPeriod"
        @change="onInboxScopeChange"
      />
      <!-- filtros proprios da tela (ex.: Atribuicoes pede time e caixa) -->
      <slot />
    </div>
    <div class="flex items-center">
      <span class="mx-2 text-sm whitespace-nowrap">
        {{ $t('REPORT.BUSINESS_HOURS') }}
      </span>
      <span>
        <ToggleSwitch
          v-model="businessHoursSelected"
          @change="onBusinessHoursToggle"
        />
      </span>
    </div>
  </div>
</template>
