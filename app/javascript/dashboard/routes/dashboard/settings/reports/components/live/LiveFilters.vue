<script setup>
import { teamDisplayName } from 'dashboard/helper/reportFormat';
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const emit = defineEmits(['filterChange']);

const { t } = useI18n();
const store = useStore();

const selectedAgent = ref(null);
const selectedDepartment = ref(null);
const selectedInbox = ref(null);

const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

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
  return [
    allOption,
    ...teams.value.map(team => ({ ...team, name: teamDisplayName(team.name) })),
  ];
});

// Lista de caixas com a opcao "todas"
const inboxOptions = computed(() => {
  const allOption = { id: null, name: t('INBOX_REPORTS.ALL_INBOXES') };
  if (!inboxes.value || inboxes.value.length === 0) {
    return [allOption];
  }
  return [allOption, ...inboxes.value];
});

const emitFilters = () => {
  emit('filterChange', {
    agent: selectedAgent.value,
    department: selectedDepartment.value,
    inbox: selectedInbox.value,
  });
};

const handleAgentChange = newValue => {
  // Atualizar o valor local
  selectedAgent.value = newValue;
  emitFilters();
};

const handleInboxChange = newValue => {
  selectedInbox.value = newValue;
  emitFilters();
};

const handleDepartmentChange = newValue => {
  // Atualizar o valor local (o v-model já faz isso, mas garantimos aqui também)
  if (newValue !== undefined) {
    selectedDepartment.value = newValue;
  }
  emitFilters();
};

onMounted(() => store.dispatch('inboxes/get'));
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
        {{ t('INBOX_REPORTS.HEADER') }}
      </label>
      <div class="multiselect-wrap--small">
        <multiselect
          v-model="selectedInbox"
          class="no-margin"
          :placeholder="t('INBOX_REPORTS.SEARCH_INBOX')"
          label="name"
          track-by="id"
          :options="inboxOptions"
          :option-height="24"
          :show-labels="false"
          @update:model-value="handleInboxChange"
          @input="handleInboxChange"
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
