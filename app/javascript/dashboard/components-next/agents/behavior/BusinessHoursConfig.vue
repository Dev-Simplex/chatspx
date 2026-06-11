<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const DAYS = [
  { value: 0, label: 'Sun' },
  { value: 1, label: 'Mon' },
  { value: 2, label: 'Tue' },
  { value: 3, label: 'Wed' },
  { value: 4, label: 'Thu' },
  { value: 5, label: 'Fri' },
  { value: 6, label: 'Sat' },
];

const OUTSIDE_ACTIONS = [
  { value: 'ignore', label: 'CAPTAIN.BEHAVIOR.BUSINESS_HOURS.ACTION_IGNORE' },
  {
    value: 'qualify_more',
    label: 'CAPTAIN.BEHAVIOR.BUSINESS_HOURS.ACTION_QUALIFY',
  },
];

const config = computed({
  get: () => props.modelValue || {},
  set: val => emit('update:modelValue', val),
});

const enabled = computed({
  get: () => config.value.enabled === true,
  set: val => emit('update:modelValue', { ...config.value, enabled: val }),
});

function updateField(key, value) {
  emit('update:modelValue', { ...config.value, [key]: value });
}

function updateDayRange(dayValue, rangeIndex, field, value) {
  const schedule = [...(config.value.schedule || [])];
  let dayEntry = schedule.find(d => d.day === dayValue);
  if (!dayEntry) {
    dayEntry = { day: dayValue, ranges: [{ start: '08:00', end: '17:00' }] };
    schedule.push(dayEntry);
  }
  const ranges = [...(dayEntry.ranges || [])];
  ranges[rangeIndex] = { ...ranges[rangeIndex], [field]: value };
  dayEntry.ranges = ranges;
  updateField(
    'schedule',
    schedule.map(d => (d.day === dayValue ? dayEntry : d))
  );
}
</script>

<template>
  <div
    id="behavior-business_hours"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <div class="flex items-center justify-between">
      <div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ $t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.DESCRIPTION') }}
        </p>
      </div>
      <input v-model="enabled" type="checkbox" class="toggle-checkbox" />
    </div>

    <div v-if="enabled" class="mt-3 space-y-3">
      <div>
        <label class="mb-1 block text-xs text-n-slate-10">Timezone</label>
        <input
          :value="config.timezone"
          type="text"
          class="w-64 rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          placeholder="America/Cuiaba"
          @change="updateField('timezone', $event.target.value)"
        />
      </div>

      <div>
        <label class="mb-1 block text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.OUTSIDE_ACTION') }}
        </label>
        <select
          :value="config.outside_hours_action || 'ignore'"
          class="rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          @change="updateField('outside_hours_action', $event.target.value)"
        >
          <option
            v-for="action in OUTSIDE_ACTIONS"
            :key="action.value"
            :value="action.value"
          >
            {{ $t(action.label) }}
          </option>
        </select>
      </div>

      <div class="space-y-2">
        <div
          v-for="day in DAYS"
          :key="day.value"
          class="flex items-center gap-2"
        >
          <span class="w-10 text-xs font-medium text-n-slate-12">
            {{ day.label }}
          </span>
          <template
            v-for="(range, idx) in (
              (config.schedule || []).find(d => d.day === day.value) || {}
            ).ranges || []"
            :key="idx"
          >
            <input
              :value="range.start"
              type="time"
              class="rounded border border-n-weak bg-white px-1 py-0.5 text-xs dark:bg-n-solid-3 dark:text-n-slate-12"
              @change="
                updateDayRange(day.value, idx, 'start', $event.target.value)
              "
            />
            <span class="text-xs text-n-slate-10">-</span>
            <input
              :value="range.end"
              type="time"
              class="rounded border border-n-weak bg-white px-1 py-0.5 text-xs dark:bg-n-solid-3 dark:text-n-slate-12"
              @change="
                updateDayRange(day.value, idx, 'end', $event.target.value)
              "
            />
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
