<script>
import WootDateRangePicker from 'dashboard/components/ui/DateRangePicker.vue';
import ReportsFiltersDateRange from './Filters/DateRange.vue';
import ReportsFiltersDateGroupBy from './Filters/DateGroupBy.vue';
import ReportsFiltersAgents from './Filters/Agents.vue';
import ReportsFiltersLabels from './Filters/Labels.vue';
import ReportsFiltersInboxes from './Filters/Inboxes.vue';
import ReportsFiltersTeams from './Filters/Teams.vue';
import ReportsFiltersRatings from './Filters/Ratings.vue';
import subDays from 'date-fns/subDays';
import { DATE_RANGE_OPTIONS } from '../constants';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

export default {
  components: {
    WootDateRangePicker,
    ReportsFiltersDateRange,
    ReportsFiltersDateGroupBy,
    ReportsFiltersAgents,
    ReportsFiltersLabels,
    ReportsFiltersInboxes,
    ReportsFiltersTeams,
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
      selectedDateRange: DATE_RANGE_OPTIONS.LAST_7_DAYS,
      selectedGroupByFilter: null,
      selectedLabel: null,
      selectedInbox: null,
      selectedTeam: null,
      selectedRating: null,
      selectedAgents: [],
      customDateRange: [new Date(), new Date()],
      businessHoursSelected: false,
    };
  },
  computed: {
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
    onDateRangeChange(selectedRange) {
      this.selectedDateRange = selectedRange;
      this.selectedGroupByFilter = this.validGroupBy;
      this.emitChange();
    },
    onCustomDateRangeChange(value) {
      this.customDateRange = value;
      this.selectedGroupByFilter = this.validGroupBy;
      this.emitChange();
    },
    onGroupingChange(payload) {
      this.selectedGroupByFilter = payload;
      this.emitChange();
    },
    handleAgentsFilterSelection(selectedAgents) {
      this.selectedAgents = selectedAgents;
      this.emitChange();
    },
    handleLabelsFilterSelection(selectedLabel) {
      this.selectedLabel = selectedLabel;
      this.emitChange();
    },
    handleInboxFilterSelection(selectedInbox) {
      this.selectedInbox = selectedInbox;
      this.emitChange();
    },
    handleTeamFilterSelection(selectedTeam) {
      this.selectedTeam = selectedTeam;
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
  <div
    class="rounded-2xl border border-n-container/60 bg-n-solid-2/80 backdrop-blur px-4 py-4 shadow-sm relative z-30"
  >
    <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
      <div
        class="w-full grid gap-3 grid-cols-[repeat(auto-fit,minmax(220px,1fr))]"
      >
        <ReportsFiltersDateRange @on-range-change="onDateRangeChange" />
        <WootDateRangePicker
          v-if="isDateRangeSelected"
          show-range
          class="no-margin auto-width"
          :value="customDateRange"
          :confirm-text="$t('REPORT.CUSTOM_DATE_RANGE.CONFIRM')"
          :placeholder="$t('REPORT.CUSTOM_DATE_RANGE.PLACEHOLDER')"
          @change="onCustomDateRangeChange"
        />
        <ReportsFiltersDateGroupBy
          v-if="showGroupByFilter && isGroupByPossible"
          :valid-group-options="validGroupOptions"
          :selected-option="selectedGroupByFilter"
          @on-grouping-change="onGroupingChange"
        />
        <ReportsFiltersAgents
          v-if="showAgentsFilter"
          @agents-filter-selection="handleAgentsFilterSelection"
        />
        <ReportsFiltersLabels
          v-if="showLabelsFilter"
          @labels-filter-selection="handleLabelsFilterSelection"
        />
        <ReportsFiltersTeams
          v-if="showTeamFilter"
          @team-filter-selection="handleTeamFilterSelection"
        />
        <ReportsFiltersInboxes
          v-if="showInboxFilter"
          @inbox-filter-selection="handleInboxFilterSelection"
        />
        <ReportsFiltersRatings
          v-if="showRatingFilter"
          @rating-filter-selection="handleRatingFilterSelection"
        />
      </div>
      <div
        v-if="showBusinessHoursSwitch"
        class="flex items-center gap-3 rounded-xl border border-n-container/40 bg-n-background/70 px-4 py-3"
      >
        <span class="text-sm text-n-slate-12 whitespace-nowrap">
          {{ $t('REPORT.BUSINESS_HOURS') }}
        </span>
        <ToggleSwitch v-model="businessHoursSelected" @change="emitChange" />
      </div>
    </div>
  </div>
</template>
