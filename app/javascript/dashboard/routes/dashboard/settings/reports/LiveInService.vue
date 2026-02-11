<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';
import LiveFilters from './components/live/LiveFilters.vue';
import AgentCard from './components/live/AgentCard.vue';
import AgentCardSkeleton from './components/live/AgentCardSkeleton.vue';
import ConversationItem from './components/live/ConversationItem.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CreepyButton from './components/live/CreepyButton.vue';

const store = useStore();
const { t } = useI18n();

const filters = ref({
  agent: null,
  department: null,
});

const isLoading = ref(true);
/** Indica se a primeira carga da tela já terminou (para mostrar preloader ao entrar pela sidebar) */
const hasInitiallyLoaded = ref(false);
const lastUpdateTime = ref(null);
const showFilters = ref(false);
const isRealtimeEnabled = ref(false);
const showWaitingSection = ref(false);
const sortBy = ref('calls'); // 'calls' | 'name_asc' | 'name_desc'

// Garagem de chamados: estado local exclusivo da tela ao vivo (não é afetado por emptyAllConversations)
const liveConversations = ref([]);

// Fonte de dados da tela = liveConversations (não mais o store global)
const allConversations = computed(() => liveConversations.value || []);
const allAgents = useMapGetter('agents/getAgents');
const allTeams = useMapGetter('teams/getTeams');

// Processar dados reais - usar getAllStatusChats para filtrar conversas abertas e pendentes
const processedAgents = computed(() => {
  if (!allAgents.value || allAgents.value.length === 0) {
    return [];
  }
  
  // Pegar todas as conversas do store e filtrar por status open/pending
  const allConversationsInStore = allConversations.value || [];
  const conversations = allConversationsInStore.filter(
    conv => conv.status === 'open' || conv.status === 'pending'
  );

  return allAgents.value
    .map(agent => {
      // Filtrar conversas atribuídas a este agente e com status open/pending
      const agentConversations = conversations.filter(conv => {
        // Verificar assignee - o sistema usa conv.meta.assignee
        const assignee = conv.meta?.assignee;
        let isAssignedToAgent = false;
        
        if (assignee && assignee.id) {
          isAssignedToAgent = Number(assignee.id) === Number(agent.id);
        }
        
        // Aceitar apenas conversas abertas ou pendentes
        const isOpenOrPending =
          conv.status === 'open' || 
          conv.status === 'pending';
        
        const matches = isAssignedToAgent && isOpenOrPending;
        
        return matches;
      });

      // Obter última mensagem de cada conversa
      const conversationsWithLastMessage = agentConversations.map(conv => {
        // As mensagens podem não estar carregadas, usar last_non_activity_message se disponível
        const messages = conv.messages || [];
        const lastMessage = messages.length > 0 
          ? messages[messages.length - 1] 
          : conv.last_non_activity_message || null;
        
        // Calcular mensagens não lidas - usar unread_count se disponível
        const unreadCount = conv.unread_count !== undefined 
          ? conv.unread_count 
          : messages.filter(
              msg => !msg.read_at && msg.message_type === 'incoming'
            ).length;

        // Determinar status da última mensagem
        let lastMessageStatus = 'sent';
        if (lastMessage) {
          if (lastMessage.read_at) {
            lastMessageStatus = 'read';
          } else if (lastMessage.message_type === 'outgoing') {
            lastMessageStatus = 'sent';
          }
        }

        // Obter informações do contato
        const contact = conv.meta?.sender || conv.sender || {};
        const contactName = contact.name || contact.identifier || contact.email || t('LIVE_REPORTS.IN_SERVICE.NO_NAME');
        const contactAvatar = contact.thumbnail || contact.avatar_url;

        // Formatar última mensagem
        let lastMessageText = t('LIVE_REPORTS.IN_SERVICE.NO_MESSAGES');
        if (lastMessage) {
          if (lastMessage.content) {
            lastMessageText = lastMessage.content;
          } else if (lastMessage.attachments && lastMessage.attachments.length > 0) {
            const attachment = lastMessage.attachments[0];
            if (attachment.file_type === 'image') {
              lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_IMAGE');
            } else if (attachment.file_type === 'audio') {
              lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_AUDIO');
            } else if (attachment.file_type === 'file') {
              lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_FILE');
            }
          }
        }

        // Obter timestamp da última mensagem ou da conversa
        // Timestamps vêm como Unix timestamp em segundos do backend
        let lastMessageTime = null;
        if (lastMessage?.created_at) {
          lastMessageTime = lastMessage.created_at;
        } else if (lastMessage?.timestamp) {
          lastMessageTime = lastMessage.timestamp;
        } else if (conv.timestamp) {
          // timestamp da conversa é last_activity_at em segundos
          lastMessageTime = conv.timestamp;
        } else if (conv.last_activity_at) {
          lastMessageTime = conv.last_activity_at;
        } else if (conv.updated_at) {
          // updated_at pode vir como float, converter para int se necessário
          lastMessageTime = typeof conv.updated_at === 'number' ? Math.floor(conv.updated_at) : conv.updated_at;
        }

        return {
          id: conv.id,
          contactName,
          contactAvatar,
          lastMessage: lastMessageText,
          lastMessageTime,
          unreadCount,
          lastMessageStatus,
        };
      })
      .sort((a, b) => {
        // Ordenar por última mensagem (mais recente primeiro)
        return new Date(b.lastMessageTime) - new Date(a.lastMessageTime);
      })
      .slice(0, 10); // Limitar a 10 conversas por agente

      // Obter status do agente
      const status = agent.availability_status || 'offline';

      // Obter teams do agente - verificar múltiplas fontes
      // Primeiro verificar team_ids diretamente (como no LiveSummary.vue)
      let agentTeamIds = agent.team_ids || [];
      
      // Se não tiver team_ids, tentar extrair de account_users
      if (!agentTeamIds || agentTeamIds.length === 0) {
        if (agent.account_users && Array.isArray(agent.account_users)) {
          agentTeamIds = agent.account_users
            .map(au => au.team_id)
            .filter(id => id !== null && id !== undefined);
        }
      }
      
      // Extrair teams (objetos) se disponível
      let agentTeams = [];
      if (agent.teams && Array.isArray(agent.teams)) {
        agentTeams = agent.teams;
      } else if (agent.account_users && Array.isArray(agent.account_users)) {
        agentTeams = agent.account_users
          .map(au => au.team)
          .filter(team => team !== null && team !== undefined);
      }

      return {
        id: agent.id,
        name: agent.available_name || agent.name || agent.email,
        avatar: agent.thumbnail || agent.avatar_url,
        status,
        totalOpenCalls: agentConversations.length,
        conversations: conversationsWithLastMessage,
        teams: agentTeams,
        team_ids: agentTeamIds,
      };
    })
    .filter(agent => agent.id); // Mostrar todos os agentes válidos
});

const filteredAgents = computed(() => {
  let filtered = [...processedAgents.value];

  // Se nenhum filtro estiver selecionado, mostrar todos
  if (!filters.value.agent && !filters.value.department) {
    return filtered;
  }

  // Filtrar por agente (se não for "Todos" - id null)
  if (filters.value.agent && filters.value.agent.id !== null) {
    filtered = filtered.filter(agent => agent.id === filters.value.agent.id);
  }

  // Filtrar por departamento (se não for "Todos" - id null)
  if (filters.value.department && filters.value.department.id !== null && filters.value.department.id !== undefined) {
    const selectedDepartmentId = filters.value.department.id;
    
    // Filtrar agentes que pertencem ao departamento selecionado
    // Usar EXATAMENTE a mesma abordagem do LiveSummary.vue
    filtered = filtered.filter(processedAgent => {
      // Buscar o agente original no store para ter acesso ao team_ids completo
      const originalAgent = allAgents.value.find(a => Number(a.id) === Number(processedAgent.id));
      
      if (!originalAgent) {
        return false;
      }
      
      // Usar EXATAMENTE a mesma lógica do LiveSummary.vue linha 79:
      // agent => agent.team_ids && agent.team_ids.includes(team.id)
      // Não converter para número, usar comparação direta como no LiveSummary
      if (originalAgent.team_ids && Array.isArray(originalAgent.team_ids)) {
        // Comparação direta como no LiveSummary - pode ser número ou string
        const hasTeam = originalAgent.team_ids.includes(selectedDepartmentId);
        
        return hasTeam;
      }
      
      // Se não tiver team_ids no agente, tentar extrair de account_users (fallback)
      if (originalAgent.account_users && Array.isArray(originalAgent.account_users) && originalAgent.account_users.length > 0) {
        const teamIdsFromAccountUsers = originalAgent.account_users
          .map(au => au.team_id)
          .filter(id => id !== null && id !== undefined);
        
        // Comparação direta sem conversão
        const hasTeam = teamIdsFromAccountUsers.includes(selectedDepartmentId);
        
        return hasTeam;
      }
      
      return false;
    });
  }

  return filtered;
});

// KPIs para o resumo visual (baseados na garagem local)
const totalChamados = computed(() => liveConversations.value.length);
const totalAgentesComConversas = computed(() =>
  processedAgents.value.filter(a => (a.totalOpenCalls || 0) > 0).length
);
const totalEmEspera = computed(() =>
  liveConversations.value.filter(
    c => c.status === 'pending' || !c.meta?.assignee?.id
  ).length
);

const lastUpdateFormatted = computed(() => {
  const t = lastUpdateTime.value;
  if (!t) return '';
  const d = t instanceof Date ? t : new Date(t);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
});

// Conversas em espera (sem agente ou pendentes) formatadas para exibição
const mapConvToDisplay = conv => {
  const messages = conv.messages || [];
  const lastMessage = messages.length > 0 ? messages[messages.length - 1] : conv.last_non_activity_message || null;
  const unreadCount = conv.unread_count !== undefined ? conv.unread_count : messages.filter(m => !m.read_at && m.message_type === 'incoming').length;
  let lastMessageStatus = 'sent';
  if (lastMessage) {
    if (lastMessage.read_at) lastMessageStatus = 'read';
    else if (lastMessage.message_type === 'outgoing') lastMessageStatus = 'sent';
  }
  const contact = conv.meta?.sender || conv.sender || {};
  const contactName = contact.name || contact.identifier || contact.email || t('LIVE_REPORTS.IN_SERVICE.NO_NAME');
  const contactAvatar = contact.thumbnail || contact.avatar_url;
  let lastMessageText = t('LIVE_REPORTS.IN_SERVICE.NO_MESSAGES');
  if (lastMessage) {
    if (lastMessage.content) lastMessageText = lastMessage.content;
    else if (lastMessage.attachments?.length) {
      const a = lastMessage.attachments[0];
      if (a.file_type === 'image') lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_IMAGE');
      else if (a.file_type === 'audio') lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_AUDIO');
      else if (a.file_type === 'file') lastMessageText = t('LIVE_REPORTS.IN_SERVICE.SENT_FILE');
    }
  }
  let lastMessageTime = lastMessage?.created_at ?? lastMessage?.timestamp ?? conv.timestamp ?? conv.last_activity_at ?? (typeof conv.updated_at === 'number' ? Math.floor(conv.updated_at) : conv.updated_at);
  return { id: conv.id, contactName, contactAvatar, lastMessage: lastMessageText, lastMessageTime, unreadCount, lastMessageStatus };
};

const waitingConversationsDisplay = computed(() =>
  liveConversations.value
    .filter(c => c.status === 'pending' || !c.meta?.assignee?.id)
    .map(mapConvToDisplay)
    .sort((a, b) => new Date(b.lastMessageTime || 0) - new Date(a.lastMessageTime || 0))
);

const sortedAgents = computed(() => {
  const list = [...filteredAgents.value];
  if (sortBy.value === 'calls') {
    list.sort((a, b) => (b.totalOpenCalls || 0) - (a.totalOpenCalls || 0));
  } else if (sortBy.value === 'name_asc') {
    list.sort((a, b) => (a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' }));
  } else if (sortBy.value === 'name_desc') {
    list.sort((a, b) => (b.name || '').localeCompare(a.name || '', undefined, { sensitivity: 'base' }));
  }
  return list;
});

const handleFilterChange = newFilters => {
  // Garantir que o filtro seja atualizado corretamente
  // Se department for null ou id for null, limpar o filtro
  filters.value = {
    agent: newFilters.agent && newFilters.agent.id !== null && newFilters.agent.id !== undefined ? newFilters.agent : null,
    department: newFilters.department && newFilters.department.id !== null && newFilters.department.id !== undefined ? newFilters.department : null,
  };
};

const fetchData = async () => {
  isLoading.value = true;
  try {
    // Fase 1: Carregar agentes e teams primeiro (layout aparece rápido)
    await Promise.all([
      store.dispatch('agents/get'),
      store.dispatch('teams/get'),
    ]);
    const agents = store.getters['agents/getAgents'] || [];
    const teams = store.getters['teams/getTeams'] || [];
    
    // Se nenhum agente tiver team_ids, tentar buscar via API de teams
    const agentsWithTeamIds = agents.filter(a => a.team_ids && Array.isArray(a.team_ids) && a.team_ids.length > 0);
    if (agentsWithTeamIds.length === 0 && teams.length > 0) {
      const TeamsAPI = (await import('dashboard/api/teams')).default;
      const teamMembersMap = new Map();
      
      // Buscar team members para cada team em paralelo
      const teamPromises = teams.map(async team => {
        try {
          const response = await TeamsAPI.getAgents({ teamId: team.id });
          if (response.data && Array.isArray(response.data)) {
            response.data.forEach(member => {
              const memberId = member.id || member.user_id;
              if (memberId) {
                if (!teamMembersMap.has(memberId)) {
                  teamMembersMap.set(memberId, []);
                }
                teamMembersMap.get(memberId).push(team.id);
              }
            });
          }
        } catch (error) {
          // Erro silencioso ao buscar membros do team
        }
      });
      
      await Promise.all(teamPromises);
      
      // Atualizar agentes com team_ids
      if (teamMembersMap.size > 0) {
        agents.forEach(agent => {
          if (teamMembersMap.has(agent.id)) {
            agent.team_ids = teamMembersMap.get(agent.id);
          } else {
            // Se o agente não está em nenhum team, inicializar com array vazio
            if (!agent.team_ids) {
              agent.team_ids = [];
            }
          }
        });
        
        // Atualizar o store com os agentes modificados
        store.commit('agents/SET_AGENTS', agents);
      }
    }

    // Carregar todas as conversas durante o preloader (open e pending em paralelo)
    const ConversationApi = (await import('dashboard/api/inbox/conversation')).default;

    const fetchPage = async (status, cursor) => {
      const res = await ConversationApi.get({
        status,
        assigneeType: 'all',
        cursor: cursor || undefined,
        sortBy: 'last_activity_at_desc',
      });
      const data = res?.data?.data ?? {};
      return {
        payload: data.payload ?? [],
        nextCursor: data.meta?.next_cursor ?? null,
      };
    };

    const loadAllWithCursor = async status => {
      const all = [];
      let cursor = null;
      do {
        const { payload, nextCursor } = await fetchPage(status, cursor);
        all.push(...payload);
        cursor = nextCursor;
      } while (cursor);
      return all;
    };

    const [openList, pendingList] = await Promise.all([
      loadAllWithCursor('open'),
      loadAllWithCursor('pending'),
    ]);
    const allConversationsToAdd = [...openList, ...pendingList];

    // Garagem: gravar na fonte local da tela (não no store global, assim emptyAllConversations não zera os totais)
    liveConversations.value = allConversationsToAdd;

    // Adicionar contatos ao store para navegação ao clicar em uma conversa
    const contacts = allConversationsToAdd.map(conv => conv.meta?.sender).filter(Boolean);
    if (contacts.length > 0) {
      store.commit('contacts/SET_CONTACTS', contacts);
    }

    lastUpdateTime.value = new Date();
  } catch (error) {
    // Erro silencioso
  } finally {
    isLoading.value = false;
    hasInitiallyLoaded.value = true;
  }
};

// Criar função de refresh com intervalo dinâmico
const refreshFn = () => {
  if (isRealtimeEnabled.value) {
    fetchData();
  }
};

// Criar instância de live refresh com intervalo de 15 segundos
const { startRefetching, stopRefetching } = useLiveRefresh(refreshFn, 15000);

const toggleRealtime = () => {
  isRealtimeEnabled.value = !isRealtimeEnabled.value;
  if (isRealtimeEnabled.value) {
    fetchData(); // Buscar imediatamente
    startRefetching();
  } else {
    stopRefetching();
  }
};

const toggleFilters = () => {
  showFilters.value = !showFilters.value;
};

const refreshData = async () => {
  await fetchData();
};

onMounted(() => {
  fetchData();
  // Não iniciar automaticamente, pois status inicial é false
});

onBeforeUnmount(() => {
  stopRefetching();
});
</script>

<template>
  <div>
    <div>
      <ReportHeader
        :header-title="$t('LIVE_REPORTS.IN_SERVICE.HEADER')"
        :header-description="$t('LIVE_REPORTS.IN_SERVICE.DESCRIPTION')"
      >
        <template #default>
          <div class="flex flex-col gap-2 items-end">
            <div class="flex items-center gap-3 flex-wrap justify-end">
              <span
                v-if="isRealtimeEnabled"
                class="flex items-center gap-1.5 text-xs font-medium text-n-teal-11"
              >
                <span class="relative flex h-2 w-2">
                  <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-n-teal-9 opacity-75" />
                  <span class="relative inline-flex h-2 w-2 rounded-full bg-n-teal-10" />
                </span>
                {{ $t('LIVE_REPORTS.IN_SERVICE.LIVE_INDICATOR') }}
              </span>
              <span
                v-if="lastUpdateFormatted"
                class="text-xs text-n-slate-11"
              >
                {{ $t('LIVE_REPORTS.IN_SERVICE.LAST_UPDATE') }}: {{ lastUpdateFormatted }}
              </span>
            </div>
            <div class="flex items-center gap-3 flex-wrap">
              <Button
                :icon="showFilters ? 'i-lucide-search-x' : 'i-lucide-search'"
                :label="showFilters ? $t('LIVE_REPORTS.IN_SERVICE.HIDE_FILTERS') : $t('LIVE_REPORTS.IN_SERVICE.SHOW_FILTERS')"
                size="sm"
                color="slate"
                variant="faded"
                @click="toggleFilters"
              />
              <div class="flex items-center gap-2">
                <CreepyButton
                  :active="isRealtimeEnabled"
                  @click="toggleRealtime"
                >
                  {{ isRealtimeEnabled ? $t('LIVE_REPORTS.IN_SERVICE.DISABLE_REALTIME') : $t('LIVE_REPORTS.IN_SERVICE.ENABLE_REALTIME') }}
                </CreepyButton>
                <span
                  v-if="isRealtimeEnabled"
                  class="text-xs text-n-slate-11 font-medium"
                >
                  {{ $t('LIVE_REPORTS.IN_SERVICE.UPDATES_EVERY') }} 15s
                </span>
                <Button
                  v-if="!isRealtimeEnabled"
                  icon="i-lucide-refresh-cw"
                  :label="$t('LIVE_REPORTS.IN_SERVICE.REFRESH')"
                  size="sm"
                  color="slate"
                  variant="faded"
                  :loading="isLoading"
                  @click="refreshData"
                />
              </div>
            </div>
          </div>
        </template>
      </ReportHeader>
    </div>
    <div class="flex flex-col gap-6 pb-6">
      <div
        v-show="showFilters"
        class="rounded-2xl border border-n-container/60 bg-n-solid-2/80 p-4 shadow-sm relative z-30"
      >
        <LiveFilters @filter-change="handleFilterChange" />
        <div
          v-if="hasInitiallyLoaded && filteredAgents.length > 0"
          class="flex flex-wrap items-center gap-2 mt-3"
        >
          <span class="text-xs font-medium text-n-slate-11">{{ $t('LIVE_REPORTS.IN_SERVICE.SORT_AGENTS') }}:</span>
          <select
            v-model="sortBy"
            class="rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12 text-sm px-3 py-1.5 outline-none focus:ring-2 focus:ring-n-brand-9"
          >
            <option value="calls">
              {{ $t('LIVE_REPORTS.IN_SERVICE.SORT_BY_CALLS') }}
            </option>
            <option value="name_asc">
              {{ $t('LIVE_REPORTS.IN_SERVICE.SORT_BY_NAME_ASC') }}
            </option>
            <option value="name_desc">
              {{ $t('LIVE_REPORTS.IN_SERVICE.SORT_BY_NAME_DESC') }}
            </option>
          </select>
        </div>
      </div>
      <div
        v-if="!isLoading || liveConversations.length > 0"
        class="grid grid-cols-1 sm:grid-cols-3 gap-3"
      >
        <div
          v-tooltip="$t('LIVE_REPORTS.IN_SERVICE.KPI_TOTAL_CALLS_TOOLTIP')"
          class="flex items-center gap-3 p-4 rounded-xl bg-n-solid-2 border border-n-weak outline-1 outline outline-n-container cursor-help"
        >
          <span class="flex items-center justify-center size-10 rounded-lg bg-n-brand-3 text-n-brand-11">
            <span class="i-lucide-phone-call size-5" />
          </span>
          <div>
            <p class="text-2xl font-semibold text-n-slate-12 m-0 leading-tight">
              {{ totalChamados }}
            </p>
            <p class="text-xs font-medium text-n-slate-11 m-0">
              {{ $t('LIVE_REPORTS.IN_SERVICE.KPI_TOTAL_CALLS') }}
            </p>
          </div>
        </div>
        <div
          v-tooltip="$t('LIVE_REPORTS.IN_SERVICE.KPI_AGENTS_ACTIVE_TOOLTIP')"
          class="flex items-center gap-3 p-4 rounded-xl bg-n-solid-2 border border-n-weak outline-1 outline outline-n-container cursor-help"
        >
          <span class="flex items-center justify-center size-10 rounded-lg bg-n-teal-3 text-n-teal-11">
            <span class="i-lucide-users size-5" />
          </span>
          <div>
            <p class="text-2xl font-semibold text-n-slate-12 m-0 leading-tight">
              {{ totalAgentesComConversas }}
            </p>
            <p class="text-xs font-medium text-n-slate-11 m-0">
              {{ $t('LIVE_REPORTS.IN_SERVICE.KPI_AGENTS_ACTIVE') }}
            </p>
          </div>
        </div>
        <div
          v-tooltip="$t('LIVE_REPORTS.IN_SERVICE.KPI_WAITING_TOOLTIP')"
          class="flex items-center gap-3 p-4 rounded-xl bg-n-solid-2 border border-n-weak outline-1 outline outline-n-container cursor-help"
        >
          <span class="flex items-center justify-center size-10 rounded-lg bg-n-amber-3 text-n-amber-11">
            <span class="i-lucide-clock size-5" />
          </span>
          <div class="flex flex-col gap-1 min-w-0">
            <p class="text-2xl font-semibold text-n-slate-12 m-0 leading-tight">
              {{ totalEmEspera }}
            </p>
            <p class="text-xs font-medium text-n-slate-11 m-0">
              {{ $t('LIVE_REPORTS.IN_SERVICE.KPI_WAITING') }}
            </p>
            <button
              v-if="totalEmEspera > 0"
              type="button"
              class="text-xs font-medium text-n-amber-11 hover:text-n-amber-12 text-left underline-offset-2 hover:underline cursor-pointer w-fit"
              @click.stop="showWaitingSection = !showWaitingSection"
            >
              {{ showWaitingSection ? $t('LIVE_REPORTS.IN_SERVICE.HIDE_WAITING') : $t('LIVE_REPORTS.IN_SERVICE.VIEW_WAITING_COUNT', { count: totalEmEspera }) }}
            </button>
          </div>
        </div>
      </div>
      <div
        v-show="showWaitingSection && totalEmEspera > 0"
        class="rounded-xl border border-n-weak bg-n-solid-2 outline-1 outline outline-n-container overflow-hidden"
      >
        <div class="px-4 py-3 border-b border-n-weak bg-n-amber-3/30 text-n-amber-11 font-medium text-sm">
          {{ $t('LIVE_REPORTS.IN_SERVICE.WAITING_SECTION_TITLE') }} ({{ totalEmEspera }})
        </div>
        <div class="max-h-[320px] overflow-y-auto scrollbar-thin scrollbar-thumb-n-weak scrollbar-track-transparent">
          <ConversationItem
            v-for="conv in waitingConversationsDisplay"
            :key="conv.id"
            :conversation="conv"
          />
        </div>
      </div>
      <div
        v-if="!hasInitiallyLoaded"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
      >
        <AgentCardSkeleton
          v-for="n in 6"
          :key="`skeleton-${n}`"
        />
      </div>
      <div
        v-else-if="hasInitiallyLoaded && !filteredAgents.length"
        class="flex items-center justify-center p-12"
      >
        <EmptyState
          :title="$t('LIVE_REPORTS.IN_SERVICE.NO_AGENTS')"
        />
      </div>
      <transition-group
        v-else
        name="agent-list"
        tag="div"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
      >
        <AgentCard
          v-for="agent in sortedAgents"
          :key="agent.id"
          :agent="agent"
        />
      </transition-group>
    </div>
  </div>
</template>

<style scoped>
.agent-list-enter-active,
.agent-list-leave-active {
  transition: all 0.3s ease;
}

.agent-list-enter-from {
  opacity: 0;
  transform: translateY(10px) scale(0.95);
}

.agent-list-leave-to {
  opacity: 0;
  transform: translateY(-10px) scale(0.95);
}

.agent-list-move {
  transition: transform 0.3s ease;
}
</style>
