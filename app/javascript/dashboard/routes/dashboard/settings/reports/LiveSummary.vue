<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import ReportHeader from './components/ReportHeader.vue';
import LiveSummaryFilters from './components/live/LiveSummaryFilters.vue';
import LiveMetricsGrid from './components/live/LiveMetricsGrid.vue';
import DepartmentTable from './components/live/DepartmentTable.vue';
import AgentTable from './components/live/AgentTable.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();
const store = useStore();

const filters = ref({
  department: null,
  agent: null,
});

const isLoading = ref(false);
const lastUpdateTime = ref(null);

// Getters do store
const allConversations = useMapGetter('conversations/getAllConversations');
const allAgents = useMapGetter('agents/getAgents');
const agentStatus = useMapGetter('agents/getAgentStatus');
const allTeams = useMapGetter('teams/getTeams');

// Calcular métricas
const metrics = computed(() => {
  const status = agentStatus.value || {};
  
  // Contar conversas por status
  const openCalls = (allConversations.value || []).filter(
    conv => conv.status === 'open'
  ).length;
  
  const callsInQueue = (allConversations.value || []).filter(
    conv => conv.status === 'pending' || conv.status === 'waiting'
  ).length;

  // Calcular usuários com/sem atendimento
  const agentsWithConversations = new Set(
    (allConversations.value || [])
      .filter(conv => conv.status === 'open' && conv.meta?.assignee)
      .map(conv => conv.meta.assignee.id)
  );
  
  const usersWithService = agentsWithConversations.size;
  const totalAgents = (allAgents.value || []).length;
  const usersWithoutService = totalAgents - usersWithService;

  // Calcular tempo médio (simplificado - seria necessário dados históricos)
  const formatTime = (hours, minutes, seconds) => {
    return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  };

  return {
    onlineUsers: status.online || 0,
    offlineUsers: status.offline || 0,
    absentUsers: status.busy || 0,
    usersWithService,
    usersWithoutService,
    callsInQueue,
    openCalls,
    avgOpenCallsTime: formatTime(0, 0, 0), // Seria calculado com dados históricos
    tmeFirstService: formatTime(0, 0, 0), // Seria calculado com dados históricos
  };
});

// Processar departamentos (teams)
const processedDepartments = computed(() => {
  if (!allTeams.value || !allAgents.value || !allConversations.value) return [];

  return allTeams.value.map(team => {
    // Agentes do time
    const teamAgents = allAgents.value.filter(
      agent => agent.team_ids && agent.team_ids.includes(team.id)
    );

    // Status dos agentes do time
    const online = teamAgents.filter(a => a.availability_status === 'online').length;
    const offline = teamAgents.filter(a => a.availability_status === 'offline').length;
    const absent = teamAgents.filter(a => a.availability_status === 'busy').length;

    // Conversas do time
    const teamConversations = allConversations.value.filter(conv => {
      const assignee = conv.meta?.assignee;
      return assignee && teamAgents.some(agent => agent.id === assignee.id);
    });

    const inQueue = teamConversations.filter(
      conv => conv.status === 'pending' || conv.status === 'waiting'
    ).length;

    const open = teamConversations.filter(conv => conv.status === 'open').length;

    return {
      name: team.name,
      online,
      offline,
      absent,
      inQueue,
      open,
    };
  }).filter(dept => dept.online + dept.offline + dept.absent > 0); // Mostrar apenas departamentos com agentes
});

// Processar atendentes
const processedAgents = computed(() => {
  if (!allAgents.value || !allConversations.value) return [];

  return allAgents.value.map(agent => {
    // Conversas do agente
    const agentConversations = allConversations.value.filter(conv => {
      const assignee = conv.meta?.assignee;
      return assignee && assignee.id === agent.id;
    });

    const open = agentConversations.filter(conv => conv.status === 'open').length;

    // Obter departamento do agente
    const agentTeams = (allTeams.value || []).filter(
      team => agent.team_ids && agent.team_ids.includes(team.id)
    );
    const department = agentTeams.length > 0 ? agentTeams[0].name : 'Sem departamento';

    return {
      id: agent.id,
      name: agent.available_name || agent.name,
      thumbnail: agent.thumbnail,
      department,
      status: agent.availability_status || 'offline',
      open,
    };
  }).sort((a, b) => b.open - a.open); // Ordenar por chamados abertos
});

const handleFilterChange = newFilters => {
  filters.value = { ...newFilters };
  fetchData();
};

const fetchData = async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('agents/get'),
      store.dispatch('conversations/fetchAllConversations'),
      store.dispatch('teams/get'),
    ]);
    lastUpdateTime.value = new Date();
  } catch (error) {
    console.error('Error fetching summary data:', error);
  } finally {
    isLoading.value = false;
  }
};

const { startRefetching, stopRefetching } = useLiveRefresh(fetchData, 10000); // Atualizar a cada 10 segundos

onMounted(() => {
  fetchData();
  startRefetching();
});

onBeforeUnmount(() => {
  stopRefetching();
});
</script>

<template>
  <div>
    <div>
      <ReportHeader
        :header-title="$t('LIVE_REPORTS.SUMMARY.HEADER')"
        :header-description="$t('LIVE_REPORTS.SUMMARY.DESCRIPTION')"
      />
      <div
        v-if="lastUpdateTime"
        class="flex items-center gap-2 text-xs text-n-slate-11 mb-4 -mt-2"
      >
        <span
          class="flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
        >
          <span class="w-1.5 h-1.5 rounded-full bg-n-teal-10 animate-pulse" />
          {{ $t('OVERVIEW_REPORTS.LIVE') }}
        </span>
        <span>
          {{ $t('LIVE_REPORTS.SUMMARY.LAST_UPDATE') }}:
          {{ lastUpdateTime.toLocaleTimeString('pt-BR') }}
        </span>
      </div>
    </div>
    <div class="flex flex-col gap-6 pb-6">
      <LiveSummaryFilters @filter-change="handleFilterChange" />
      <div v-if="isLoading && !processedDepartments.length" class="flex items-center justify-center p-12">
        <Spinner />
        <span class="ml-2 text-n-slate-11">
          {{ $t('LIVE_REPORTS.SUMMARY.LOADING') }}
        </span>
      </div>
      <template v-else>
        <LiveMetricsGrid :metrics="metrics" />
        <div class="flex flex-col gap-6">
          <div class="table-wrapper">
            <DepartmentTable
              :departments="processedDepartments"
              :is-loading="isLoading"
            />
          </div>
          <div class="table-wrapper">
            <AgentTable
              :agents="processedAgents"
              :is-loading="isLoading"
            />
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.table-wrapper {
  animation: fadeIn 0.5s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.table-grid-enter-active,
.table-grid-leave-active {
  transition: all 0.3s ease;
}

.table-grid-enter-from {
  opacity: 0;
  transform: scale(0.95);
}

.table-grid-leave-to {
  opacity: 0;
  transform: scale(0.95);
}
</style>
