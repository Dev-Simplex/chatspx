<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import { useI18n } from 'vue-i18n';
import TeamsAPI from 'dashboard/api/teams';
import LiveReportsAPI from 'dashboard/api/liveReports';
import ReportHeader from './components/ReportHeader.vue';
import LiveFilters from './components/live/LiveFilters.vue';
import AgentCard from './components/live/AgentCard.vue';
import AgentCardSkeleton from './components/live/AgentCardSkeleton.vue';
import ConversationItem from './components/live/ConversationItem.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CreepyButton from './components/live/CreepyButton.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';

const PREVIEW_LIMIT = 5;
const PREVIEW_CONCURRENCY = 4;
const REALTIME_INTERVAL_LABEL = '15s';

const store = useStore();
const { t } = useI18n();

const filters = ref({
  agent: null,
  department: null,
});

const isInitialLoading = ref(true);
const isRefreshing = ref(false);
const hasInitiallyLoaded = ref(false);
const lastUpdateTime = ref(null);
const showFilters = ref(false);
const isRealtimeEnabled = ref(false);
const showWaitingSection = ref(false);
const sortBy = ref('calls'); // 'calls' | 'name_asc' | 'name_desc'

const overview = ref({
  generated_at: null,
  totals: {
    in_service: 0,
    waiting: 0,
    agents_with_conversations: 0,
  },
  agents: [],
});

const agentPreviewsById = ref({});

const previewQueue = ref([]);
const activePreviewRequests = ref(0);

const teamMembersByTeamId = ref({});
const teamMembersLoadingByTeamId = ref({});

const allAgents = useMapGetter('agents/getAgents');

function createPreviewState() {
  return {
    items: [],
    nextCursor: null,
    hasMore: false,
    loading: false,
    loaded: false,
    queued: false,
    error: false,
    lastFetchedAt: null,
  };
}

const waitingPreview = ref(createPreviewState());

const normalizeOverview = data => {
  const totals = data?.totals || {};
  return {
    generated_at: data?.generated_at || null,
    totals: {
      in_service: Number(totals.in_service || 0),
      waiting: Number(totals.waiting || 0),
      agents_with_conversations: Number(totals.agents_with_conversations || 0),
    },
    agents: Array.isArray(data?.agents) ? data.agents : [],
  };
};

const ensureAgentPreviewState = agentId => {
  if (!agentPreviewsById.value[agentId]) {
    agentPreviewsById.value[agentId] = createPreviewState();
  }

  return agentPreviewsById.value[agentId];
};

const mapConversationPayload = conversation => ({
  id: conversation.id,
  contactName:
    conversation.contact_name || t('LIVE_REPORTS.IN_SERVICE.NO_NAME'),
  contactAvatar: conversation.contact_avatar,
  lastMessage:
    conversation.last_message || t('LIVE_REPORTS.IN_SERVICE.NO_MESSAGES'),
  lastMessageTime: conversation.last_message_time,
  unreadCount: Number(conversation.unread_count || 0),
  lastMessageStatus: conversation.last_message_status || 'sent',
  status: conversation.status,
});

const fetchOverview = async () => {
  const previousAgentMetrics = new Map(
    (overview.value.agents || []).map(metric => [
      Number(metric.assignee_id),
      Number(metric.in_service || 0),
    ])
  );
  const previousWaitingCount = Number(overview.value.totals?.waiting || 0);

  const response = await LiveReportsAPI.getInServiceOverview();
  const nextOverview = normalizeOverview(response?.data);
  overview.value = nextOverview;
  lastUpdateTime.value = new Date();

  const nextAgentMetrics = new Map(
    nextOverview.agents.map(metric => [
      Number(metric.assignee_id),
      Number(metric.in_service || 0),
    ])
  );

  const changedAgentIds = [];

  nextAgentMetrics.forEach((nextCount, assigneeId) => {
    if ((previousAgentMetrics.get(assigneeId) || 0) !== nextCount) {
      changedAgentIds.push(assigneeId);
    }
  });

  previousAgentMetrics.forEach((previousCount, assigneeId) => {
    if (!nextAgentMetrics.has(assigneeId) && previousCount > 0) {
      changedAgentIds.push(assigneeId);
    }
  });

  return {
    changedAgentIds: [...new Set(changedAgentIds)],
    waitingChanged:
      previousWaitingCount !== Number(nextOverview.totals.waiting || 0),
  };
};

const fetchAgentPreview = async (
  agentId,
  { append = false, force = false } = {}
) => {
  const state = ensureAgentPreviewState(agentId);

  if (state.loading) return;
  if (state.loaded && !append && !force) return;
  if (append && !state.nextCursor) return;

  state.loading = true;
  state.error = false;

  try {
    const params = {
      scope: 'agent',
      assignee_id: agentId,
      limit: PREVIEW_LIMIT,
    };

    if (append && state.nextCursor) {
      params.cursor = state.nextCursor;
    }

    const response = await LiveReportsAPI.getInServiceConversations(params);
    const payload = Array.isArray(response?.data?.payload)
      ? response.data.payload.map(mapConversationPayload)
      : [];

    state.items = append ? [...state.items, ...payload] : payload;
    state.nextCursor = response?.data?.meta?.next_cursor || null;
    state.hasMore = Boolean(response?.data?.meta?.has_more);
    state.loaded = true;
    state.lastFetchedAt = Date.now();
  } catch {
    state.error = true;
  } finally {
    state.loading = false;
    state.queued = false;
  }
};

const fetchWaitingPreview = async ({ append = false, force = false } = {}) => {
  const state = waitingPreview.value;

  if (state.loading) return;
  if (state.loaded && !append && !force) return;
  if (append && !state.nextCursor) return;

  state.loading = true;
  state.error = false;

  try {
    const params = {
      scope: 'waiting',
      limit: PREVIEW_LIMIT,
    };

    if (append && state.nextCursor) {
      params.cursor = state.nextCursor;
    }

    const response = await LiveReportsAPI.getInServiceConversations(params);
    const payload = Array.isArray(response?.data?.payload)
      ? response.data.payload.map(mapConversationPayload)
      : [];

    state.items = append ? [...state.items, ...payload] : payload;
    state.nextCursor = response?.data?.meta?.next_cursor || null;
    state.hasMore = Boolean(response?.data?.meta?.has_more);
    state.loaded = true;
    state.lastFetchedAt = Date.now();
  } catch {
    state.error = true;
  } finally {
    state.loading = false;
  }
};

const refreshLoadedAgentPreviews = async (agentIds = null) => {
  const idsToRefresh =
    agentIds ||
    Object.entries(agentPreviewsById.value)
      .filter(([, state]) => state.loaded)
      .map(([agentId]) => Number(agentId));

  if (!idsToRefresh.length) {
    return;
  }

  for (let idx = 0; idx < idsToRefresh.length; idx += PREVIEW_CONCURRENCY) {
    const batch = idsToRefresh.slice(idx, idx + PREVIEW_CONCURRENCY);
    // eslint-disable-next-line no-await-in-loop
    await Promise.all(
      batch.map(agentId => fetchAgentPreview(agentId, { force: true }))
    );
  }
};

function drainPreviewQueue() {
  while (
    activePreviewRequests.value < PREVIEW_CONCURRENCY &&
    previewQueue.value.length > 0
  ) {
    const agentId = previewQueue.value.shift();
    activePreviewRequests.value += 1;

    fetchAgentPreview(agentId).finally(() => {
      activePreviewRequests.value -= 1;
      drainPreviewQueue();
    });
  }
}

function enqueueAgentPreview(agentId) {
  const state = ensureAgentPreviewState(agentId);

  if (state.loaded || state.loading || state.queued) {
    return;
  }

  state.queued = true;
  previewQueue.value.push(agentId);
  drainPreviewQueue();
}

const refreshFn = async () => {
  if (!isRealtimeEnabled.value) return;

  try {
    const { changedAgentIds, waitingChanged } = await fetchOverview();
    const loadedChangedAgentIds = changedAgentIds.filter(agentId =>
      Boolean(ensureAgentPreviewState(agentId).loaded)
    );

    await refreshLoadedAgentPreviews(loadedChangedAgentIds);

    if (waitingPreview.value.loaded && waitingChanged) {
      await fetchWaitingPreview({ force: true });
    }
  } catch {
    // No-op
  }
};

const { startRefetching, stopRefetching } = useLiveRefresh(refreshFn, 15000);

const hasAgentsMissingTeamIds = computed(() =>
  (allAgents.value || []).some(
    agent => !Array.isArray(agent.team_ids) || agent.team_ids.length === 0
  )
);

const metricByAgentId = computed(() => {
  const metricMap = new Map();
  (overview.value.agents || []).forEach(metric => {
    metricMap.set(Number(metric.assignee_id), {
      in_service: Number(metric.in_service || 0),
      open: Number(metric.open || 0),
      pending: Number(metric.pending || 0),
    });
  });
  return metricMap;
});

const processedAgents = computed(() => {
  if (!allAgents.value || allAgents.value.length === 0) {
    return [];
  }

  return allAgents.value.map(agent => {
    const metrics = metricByAgentId.value.get(Number(agent.id)) || {
      in_service: 0,
      open: 0,
      pending: 0,
    };
    const previewState =
      agentPreviewsById.value[agent.id] || createPreviewState();

    return {
      id: agent.id,
      name: agent.available_name || agent.name || agent.email,
      avatar: agent.thumbnail || agent.avatar_url,
      status: agent.availability_status || 'offline',
      totalOpenCalls: metrics.in_service,
      conversations: previewState.items,
      conversationsLoading: previewState.loading,
      conversationsLoaded: previewState.loaded,
      hasMoreConversations: previewState.hasMore,
      team_ids: Array.isArray(agent.team_ids) ? agent.team_ids : [],
    };
  });
});

const selectedDepartmentTeamMembers = computed(() => {
  const selectedDepartmentId = filters.value.department?.id;
  if (selectedDepartmentId === null || selectedDepartmentId === undefined) {
    return null;
  }

  return teamMembersByTeamId.value[selectedDepartmentId] || null;
});

const filteredAgents = computed(() => {
  let filtered = [...processedAgents.value];

  if (
    filters.value.agent &&
    filters.value.agent.id !== null &&
    filters.value.agent.id !== undefined
  ) {
    filtered = filtered.filter(
      agent => Number(agent.id) === Number(filters.value.agent.id)
    );
  }

  if (
    filters.value.department &&
    filters.value.department.id !== null &&
    filters.value.department.id !== undefined
  ) {
    const selectedDepartmentId = filters.value.department.id;
    const fallbackMembers = selectedDepartmentTeamMembers.value || [];

    filtered = filtered.filter(agent => {
      const agentTeamIds = Array.isArray(agent.team_ids) ? agent.team_ids : [];

      if (agentTeamIds.length > 0) {
        return (
          agentTeamIds.includes(selectedDepartmentId) ||
          agentTeamIds.map(Number).includes(Number(selectedDepartmentId))
        );
      }

      if (fallbackMembers.length > 0) {
        return fallbackMembers.includes(Number(agent.id));
      }

      return false;
    });
  }

  return filtered;
});

const sortedAgents = computed(() => {
  const list = [...filteredAgents.value];

  if (sortBy.value === 'calls') {
    list.sort((a, b) => (b.totalOpenCalls || 0) - (a.totalOpenCalls || 0));
  } else if (sortBy.value === 'name_asc') {
    list.sort((a, b) =>
      (a.name || '').localeCompare(b.name || '', undefined, {
        sensitivity: 'base',
      })
    );
  } else if (sortBy.value === 'name_desc') {
    list.sort((a, b) =>
      (b.name || '').localeCompare(a.name || '', undefined, {
        sensitivity: 'base',
      })
    );
  }

  return list;
});

const totalChamados = computed(() =>
  Number(overview.value.totals?.in_service || 0)
);
const totalAgentesComConversas = computed(() =>
  Number(overview.value.totals?.agents_with_conversations || 0)
);
const totalEmEspera = computed(() =>
  Number(overview.value.totals?.waiting || 0)
);

const waitingConversationsDisplay = computed(
  () => waitingPreview.value.items || []
);

const lastUpdateFormatted = computed(() => {
  const timeValue = lastUpdateTime.value;
  if (!timeValue) return '';

  const date = timeValue instanceof Date ? timeValue : new Date(timeValue);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
});

const ensureTeamMembersForDepartment = async teamId => {
  if (!teamId || !hasAgentsMissingTeamIds.value) return;
  if (
    teamMembersByTeamId.value[teamId] ||
    teamMembersLoadingByTeamId.value[teamId]
  )
    return;

  teamMembersLoadingByTeamId.value[teamId] = true;
  try {
    const response = await TeamsAPI.getAgents({ teamId });
    const members = Array.isArray(response?.data) ? response.data : [];
    const ids = members
      .map(member => Number(member.id || member.user_id))
      .filter(Boolean);

    teamMembersByTeamId.value[teamId] = ids;
  } catch {
    teamMembersByTeamId.value[teamId] = [];
  } finally {
    teamMembersLoadingByTeamId.value[teamId] = false;
  }
};

const handleFilterChange = newFilters => {
  filters.value = {
    agent:
      newFilters.agent &&
      newFilters.agent.id !== null &&
      newFilters.agent.id !== undefined
        ? newFilters.agent
        : null,
    department:
      newFilters.department &&
      newFilters.department.id !== null &&
      newFilters.department.id !== undefined
        ? newFilters.department
        : null,
  };

  if (filters.value.department?.id) {
    ensureTeamMembersForDepartment(filters.value.department.id);
  }
};

const fetchInitialData = async () => {
  isInitialLoading.value = true;

  try {
    await Promise.all([
      store.dispatch('agents/get'),
      store.dispatch('teams/get'),
      fetchOverview(),
    ]);

    await nextTick();

    sortedAgents.value.slice(0, PREVIEW_CONCURRENCY).forEach(agent => {
      enqueueAgentPreview(agent.id);
    });
  } catch {
    // No-op
  } finally {
    isInitialLoading.value = false;
    hasInitiallyLoaded.value = true;
  }
};

const refreshData = async () => {
  isRefreshing.value = true;

  try {
    await fetchOverview();
    await refreshLoadedAgentPreviews();

    if (waitingPreview.value.loaded) {
      await fetchWaitingPreview({ force: true });
    }
  } catch {
    // No-op
  } finally {
    isRefreshing.value = false;
  }
};

const toggleRealtime = () => {
  isRealtimeEnabled.value = !isRealtimeEnabled.value;

  if (isRealtimeEnabled.value) {
    refreshFn();
    startRefetching();
  } else {
    stopRefetching();
  }
};

const toggleFilters = () => {
  showFilters.value = !showFilters.value;
};

const onAgentObserved = agentId => {
  enqueueAgentPreview(agentId);
};

const loadMoreAgentConversations = agentId => {
  fetchAgentPreview(agentId, { append: true, force: true });
};

const toggleWaitingSection = async () => {
  showWaitingSection.value = !showWaitingSection.value;

  if (showWaitingSection.value && !waitingPreview.value.loaded) {
    await fetchWaitingPreview();
  }
};

const loadMoreWaitingConversations = () => {
  fetchWaitingPreview({ append: true, force: true });
};

onMounted(() => {
  fetchInitialData();
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
                  <span
                    class="absolute inline-flex h-full w-full animate-ping rounded-full bg-n-teal-9 opacity-75"
                  />
                  <span
                    class="relative inline-flex h-2 w-2 rounded-full bg-n-teal-10"
                  />
                </span>
                {{ $t('LIVE_REPORTS.IN_SERVICE.LIVE_INDICATOR') }}
              </span>
              <span v-if="lastUpdateFormatted" class="text-xs text-n-slate-11">
                {{ $t('LIVE_REPORTS.IN_SERVICE.LAST_UPDATE') }}:
                {{ lastUpdateFormatted }}
              </span>
            </div>
            <div class="flex items-center gap-3 flex-wrap">
              <Button
                :icon="showFilters ? 'i-lucide-search-x' : 'i-lucide-search'"
                :label="
                  showFilters
                    ? $t('LIVE_REPORTS.IN_SERVICE.HIDE_FILTERS')
                    : $t('LIVE_REPORTS.IN_SERVICE.SHOW_FILTERS')
                "
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
                  {{
                    isRealtimeEnabled
                      ? $t('LIVE_REPORTS.IN_SERVICE.DISABLE_REALTIME')
                      : $t('LIVE_REPORTS.IN_SERVICE.ENABLE_REALTIME')
                  }}
                </CreepyButton>
                <span
                  v-if="isRealtimeEnabled"
                  class="text-xs text-n-slate-11 font-medium"
                >
                  {{ $t('LIVE_REPORTS.IN_SERVICE.UPDATES_EVERY') }}
                  {{ REALTIME_INTERVAL_LABEL }}
                </span>
                <Button
                  v-if="!isRealtimeEnabled"
                  icon="i-lucide-refresh-cw"
                  :label="$t('LIVE_REPORTS.IN_SERVICE.REFRESH')"
                  size="sm"
                  color="slate"
                  variant="faded"
                  :loading="isRefreshing"
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
          <span class="text-xs font-medium text-n-slate-11">
            {{ $t('LIVE_REPORTS.IN_SERVICE.SORT_AGENTS') }}:
          </span>
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
        v-if="hasInitiallyLoaded"
        class="grid grid-cols-1 sm:grid-cols-3 gap-3"
      >
        <div
          v-tooltip="$t('LIVE_REPORTS.IN_SERVICE.KPI_TOTAL_CALLS_TOOLTIP')"
          class="flex items-center gap-3 p-4 rounded-xl bg-n-solid-2 border border-n-weak outline-1 outline outline-n-container cursor-help"
        >
          <span
            class="flex items-center justify-center size-10 rounded-lg bg-n-brand-3 text-n-brand-11"
          >
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
          <span
            class="flex items-center justify-center size-10 rounded-lg bg-n-teal-3 text-n-teal-11"
          >
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
          <span
            class="flex items-center justify-center size-10 rounded-lg bg-n-amber-3 text-n-amber-11"
          >
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
              @click.stop="toggleWaitingSection"
            >
              {{
                showWaitingSection
                  ? $t('LIVE_REPORTS.IN_SERVICE.HIDE_WAITING')
                  : $t('LIVE_REPORTS.IN_SERVICE.VIEW_WAITING_COUNT', {
                      count: totalEmEspera,
                    })
              }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-show="showWaitingSection && totalEmEspera > 0"
        class="rounded-xl border border-n-weak bg-n-solid-2 outline-1 outline outline-n-container overflow-hidden"
      >
        <div
          class="px-4 py-3 border-b border-n-weak bg-n-amber-3/30 text-n-amber-11 font-medium text-sm"
        >
          {{ $t('LIVE_REPORTS.IN_SERVICE.WAITING_SECTION_TITLE') }} ({{
            totalEmEspera
          }})
        </div>

        <div
          class="max-h-[320px] overflow-y-auto scrollbar-thin scrollbar-thumb-n-weak scrollbar-track-transparent"
        >
          <div
            v-if="waitingPreview.loading && !waitingConversationsDisplay.length"
            class="p-4 text-sm text-n-slate-11"
          >
            {{ $t('LIVE_REPORTS.IN_SERVICE.LOADING') }}
          </div>

          <div
            v-else-if="!waitingConversationsDisplay.length"
            class="p-4 text-sm text-n-slate-11"
          >
            {{ $t('LIVE_REPORTS.IN_SERVICE.NO_CONVERSATIONS') }}
          </div>

          <ConversationItem
            v-for="conv in waitingConversationsDisplay"
            :key="conv.id"
            :conversation="conv"
          />
        </div>

        <div
          v-if="waitingPreview.hasMore"
          class="px-4 py-3 border-t border-n-weak"
        >
          <Button
            size="sm"
            color="slate"
            variant="faded"
            :loading="waitingPreview.loading"
            :label="$t('LIVE_REPORTS.IN_SERVICE.LOAD_MORE_CONVERSATIONS')"
            @click="loadMoreWaitingConversations"
          />
        </div>
      </div>

      <div
        v-if="!hasInitiallyLoaded"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
      >
        <AgentCardSkeleton v-for="n in 6" :key="`skeleton-${n}`" />
      </div>
      <div
        v-else-if="hasInitiallyLoaded && !filteredAgents.length"
        class="flex items-center justify-center p-12"
      >
        <EmptyState :title="$t('LIVE_REPORTS.IN_SERVICE.NO_AGENTS')" />
      </div>
      <transition-group
        v-else
        name="agent-list"
        tag="div"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
      >
        <div v-for="agent in sortedAgents" :key="agent.id" class="relative">
          <AgentCard
            :agent="agent"
            :is-conversations-loading="agent.conversationsLoading"
            :conversations-loaded="agent.conversationsLoaded"
            :has-more-conversations="agent.hasMoreConversations"
            @load-more-conversations="loadMoreAgentConversations(agent.id)"
          />
          <IntersectionObserver @observed="onAgentObserved(agent.id)" />
        </div>
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
