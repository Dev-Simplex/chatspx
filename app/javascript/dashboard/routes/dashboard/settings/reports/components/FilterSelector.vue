<script>
import ReportPeriodPicker from 'dashboard/components-next/reports/ui/ReportPeriodPicker.vue';
import ReportsFiltersDateGroupBy from './Filters/DateGroupBy.vue';
import ReportScopeFilters from 'dashboard/components-next/reports/ui/ReportScopeFilters.vue';
import ReportsFiltersLabels from './Filters/Labels.vue';
import ReportsFiltersRatings from './Filters/Ratings.vue';
import subDays from 'date-fns/subDays';
import { DATE_RANGE_OPTIONS } from '../constants';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

export default {
  components: {
    ReportPeriodPicker,
    ReportsFiltersDateGroupBy,
    ReportScopeFilters,
    ReportsFiltersLabels,
    ReportsFiltersRatings,
    ToggleSwitch,
  },
  props: {
    showGroupByFilter: {
      type: Boolean,
      default: false,
    },
    showAgentsFilter: {
      type: Boolean,
      default: false,
    },
    showLabelsFilter: {
      type: Boolean,
      default: false,
    },
    showInboxFilter: {
      type: Boolean,
      default: false,
    },
    showRatingFilter: {
      type: Boolean,
      default: false,
    },
    showTeamFilter: {
      type: Boolean,
      default: false,
    },
    showBusinessHoursSwitch: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['filterChange'],
  data() {
    return {
      // default value, need not be translated
      // o periodo vem sempre do ReportPeriodPicker, como intervalo de datas
      selectedDateRange: DATE_RANGE_OPTIONS.CUSTOM_DATE_RANGE,
      selectedGroupByFilter: null,
      selectedLabel: null,
      selectedInbox: null,
      selectedTeam: null,
      selectedRating: null,
      selectedAgents: [],
      customDateRange: [subDays(new Date(), 6), new Date()],
      businessHoursSelected: false,
    };
  },
  computed: {
    // Caixa, time e atendente, um botao cada (uma opcao por recorte), nos mesmos campos de antes.
    popoverGroups() {
      return [
        this.showInboxFilter && 'inbox',
        this.showTeamFilter && 'team',
        this.showAgentsFilter && 'agent',
      ].filter(Boolean);
    },
    popoverSelection: {
      get() {
        return {
          inbox: this.selectedInbox?.id || null,
          team: this.selectedTeam?.id || null,
          agent: this.selectedAgents[0]?.id || null,
        };
      },
      set(value) {
        this.selectedInbox = value.inbox ? { id: value.inbox } : null;
        this.selectedTeam = value.team ? { id: value.team } : null;
        this.selectedAgents = value.agent ? [{ id: value.agent }] : [];
        this.emitChange();
      },
    },
    isDateRangeSelected() {
      return (
        this.selectedDateRange.id === DATE_RANGE_OPTIONS.CUSTOM_DATE_RANGE.id
      );
    },
    isGroupByPossible() {
      return this.selectedDateRange.id !== DATE_RANGE_OPTIONS.LAST_7_DAYS.id;
    },
    to() {
      if (this.isDateRangeSelected) {
        return getUnixEndOfDay(this.customDateRange[1]);
      }
      return getUnixEndOfDay(new Date());
    },
    from() {
      if (this.isDateRangeSelected) {
        return getUnixStartOfDay(this.customDateRange[0]);
      }

      const { offset } = this.selectedDateRange;
      const fromDate = subDays(new Date(), offset);
      return getUnixStartOfDay(fromDate);
    },
    validGroupOptions() {
      return this.selectedDateRange.groupByOptions;
    },
    validGroupBy() {
      if (!this.selectedGroupByFilter) {
        return this.validGroupOptions[0];
      }

      const validIds = this.validGroupOptions.map(opt => opt.id);
      if (validIds.includes(this.selectedGroupByFilter.id)) {
        return this.selectedGroupByFilter;
      }
      return this.validGroupOptions[0];
    },
  },
  mounted() {
    this.emitChange();
  },
  methods: {
    emitChange() {
      const {
        from,
        to,
        selectedGroupByFilter: groupBy,
        businessHoursSelected: businessHours,
        selectedAgents,
        selectedLabel,
        selectedInbox,
        selectedTeam,
        selectedRating,
      } = this;
      this.$emit('filterChange', {
        from,
        to,
        groupBy,
        businessHours,
        selectedAgents,
        selectedLabel,
        selectedInbox,
        selectedTeam,
        selectedRating,
      });
    },
    onPeriodChange([start, end]) {
      this.customDateRange = [start, end];
      this.selectedGroupByFilter = this.validGroupBy;
      this.emitChange();
    },
    onGroupingChange(payload) {
      this.selectedGroupByFilter = payload;
      this.emitChange();
    },
    handleLabelsFilterSelection(selectedLabel) {
      this.selectedLabel = selectedLabel;
      this.emitChange();
    },
    handleRatingFilterSelection(selectedRating) {
      this.selectedRating = selectedRating;
      this.emitChange();
    },
  },
};
</script>

<template>
  <div class="relative z-30">
    <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
      <div
        class="w-full grid gap-3 grid-cols-[repeat(auto-fit,minmax(220px,1fr))]"
      >
        <ReportPeriodPicker
          v-model:date-range="customDateRange"
          @date-range-changed="onPeriodChange"
        />
        <ReportsFiltersDateGroupBy
          v-if="showGroupByFilter && isGroupByPossible"
          :valid-group-options="validGroupOptions"
          :selected-option="selectedGroupByFilter"
          @on-grouping-change="onGroupingChange"
        />
        <ReportScopeFilters
          v-if="popoverGroups.length"
          v-model="popoverSelection"
          :groups="popoverGroups"
          :period="{ since: from, until: to }"
        />
        <ReportsFiltersLabels
          v-if="showLabelsFilter"
          @labels-filter-selection="handleLabelsFilterSelection"
        />
        <ReportsFiltersRatings
          v-if="showRatingFilter"
          @rating-filter-selection="handleRatingFilterSelection"
        />
      </div>
      <div
        v-if="showBusinessHoursSwitch"
        class="flex items-center gap-3 rounded-lg border border-n-weak px-3 h-8"
      >
        <span class="text-sm text-n-slate-12 whitespace-nowrap">
          {{ $t('REPORT.BUSINESS_HOURS') }}
        </span>
        <ToggleSwitch v-model="businessHoursSelected" @change="emitChange" />
      </div>
    </div>
  </div>
</template>
