<script setup>
import { ref, computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const emit = defineEmits(['filterChange']);

const { t } = useI18n();

const selectedAgent = ref(null);
const selectedDepartment = ref(null);

const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

// Criar lista de agentes com opção "Todos"
const agentOptions = computed(() => {
  const allOption = {
    id: null,
    name: t('LIVE_REPORTS.IN_SERVICE.FILTERS.ALL_AGENTS'),
  };
  if (!agents.value || agents.value.length === 0) {
    return [allOption];
  }
  return [allOption, ...agents.value];
});

// Criar lista de departamentos com opção "Todos"
const departmentOptions = computed(() => {
  const allOption = {
    id: null,
    name: t('LIVE_REPORTS.IN_SERVICE.FILTERS.ALL_DEPARTMENTS'),
  };
  if (!teams.value || teams.value.length === 0) {
    return [allOption];
  }
  return [allOption, ...teams.value];
});

const handleAgentChange = newValue => {
  // Atualizar o valor local
  selectedAgent.value = newValue;

  // Emitir evento com os filtros atualizados
  emit('filterChange', {
    agent: selectedAgent.value,
    department: selectedDepartment.value,
  });
};

const handleDepartmentChange = newValue => {
  // Atualizar o valor local (o v-model já faz isso, mas garantimos aqui também)
  if (newValue !== undefined) {
    selectedDepartment.value = newValue;
  }

  // Emitir evento com os filtros atualizados
  emit('filterChange', {
    agent: selectedAgent.value,
    department: selectedDepartment.value,
  });
};
</script>

<template>
  <div class="flex flex-col gap-3 md:flex-row">
    <div class="flex-1 w-full">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12 block">
        {{ t('LIVE_REPORTS.IN_SERVICE.FILTERS.USER_NAME') }}
      </label>
      <div class="multiselect-wrap--small">
        <multiselect
          v-model="selectedAgent"
          class="no-margin"
          :placeholder="
            t('LIVE_REPORTS.IN_SERVICE.FILTERS.USER_NAME_PLACEHOLDER')
          "
          label="name"
          track-by="id"
          :options="agentOptions"
          :option-height="24"
          :show-labels="false"
          @update:model-value="handleAgentChange"
          @input="handleAgentChange"
        />
      </div>
    </div>
    <div class="flex-1 w-full">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12 block">
        {{ t('LIVE_REPORTS.IN_SERVICE.FILTERS.DEPARTMENT') }}
      </label>
      <div class="multiselect-wrap--small">
        <multiselect
          v-model="selectedDepartment"
          class="no-margin"
          :placeholder="
            t('LIVE_REPORTS.IN_SERVICE.FILTERS.DEPARTMENT_PLACEHOLDER')
          "
          label="name"
          track-by="id"
          :options="departmentOptions"
          :option-height="24"
          :show-labels="false"
          @update:model-value="handleDepartmentChange"
          @input="handleDepartmentChange"
        />
      </div>
    </div>
  </div>
</template>
