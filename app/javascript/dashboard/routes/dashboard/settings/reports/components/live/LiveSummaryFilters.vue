<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const store = useStore();

const selectedDepartment = ref(null);
const selectedAgent = ref(null);

const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const emit = defineEmits(['filterChange']);

const handleFilterChange = () => {
  emit('filterChange', {
    department: selectedDepartment.value,
    agent: selectedAgent.value,
  });
};

watch(
  () => teams.value,
  () => {
    if (teams.value && teams.value.length > 0) {
      store.dispatch('teams/get');
    }
  },
  { immediate: true }
);

watch(
  () => agents.value,
  () => {
    if (agents.value && agents.value.length > 0) {
      store.dispatch('agents/get');
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-3 md:flex-row">
    <div class="flex-1 w-full">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12 block">
        {{ t('LIVE_REPORTS.SUMMARY.FILTERS.DEPARTMENT') }}
      </label>
      <div class="multiselect-wrap--small">
        <multiselect
          v-model="selectedDepartment"
          class="no-margin"
          :placeholder="t('LIVE_REPORTS.SUMMARY.FILTERS.DEPARTMENT_PLACEHOLDER')"
          label="name"
          track-by="id"
          :options="teams"
          :option-height="24"
          :show-labels="false"
          @update:model-value="handleFilterChange"
        />
      </div>
    </div>
    <div class="flex-1 w-full">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12 block">
        {{ t('LIVE_REPORTS.SUMMARY.FILTERS.AGENT') }}
      </label>
      <div class="multiselect-wrap--small">
        <multiselect
          v-model="selectedAgent"
          class="no-margin"
          :placeholder="t('LIVE_REPORTS.SUMMARY.FILTERS.AGENT_PLACEHOLDER')"
          label="name"
          track-by="id"
          :options="agents"
          :option-height="24"
          :show-labels="false"
          @update:model-value="handleFilterChange"
        />
      </div>
    </div>
  </div>
</template>

