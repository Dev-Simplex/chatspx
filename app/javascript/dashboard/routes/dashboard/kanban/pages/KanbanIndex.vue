<script setup>
import { onMounted, computed, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import KanbanBoard from 'dashboard/components-next/Kanban/KanbanBoard.vue';
import ListView from 'dashboard/components-next/Kanban/ListView.vue';
import CalendarView from 'dashboard/components-next/Kanban/CalendarView.vue';
import KanbanFilterSelect from 'dashboard/components-next/Kanban/KanbanFilterSelect.vue';
import FunnelForm from 'dashboard/components-next/Kanban/FunnelForm.vue';
import ScheduledMessageForm from 'dashboard/components-next/Kanban/ScheduledMessageForm.vue';
import ScheduledMessagesDrawer from 'dashboard/components-next/Kanban/ScheduledMessagesDrawer.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const funnels = computed(() => store.getters['kanban/getFunnels']);
const activeFunnelId = computed(
  () => store.getters['kanban/getActiveFunnelId']
);
const activeFunnel = computed(() => {
  if (!activeFunnelId.value) return null;
  return (
    funnels.value.find(funnel => funnel.id === activeFunnelId.value) || null
  );
});
const viewMode = computed(
  () => store.getters['kanban/getViewMode'] || 'kanban'
);
const viewFilters = computed(() => store.getters['kanban/getViewFilters']);
const scheduledMessages = computed(
  () => store.getters['kanban/getScheduledMessages']
);

const showFunnelForm = ref(false);
const showScheduledMessageForm = ref(false);
const selectedFunnel = ref(null);
const selectedConversation = ref(null);
const selectedScheduledMessage = ref(null);
const selectedDate = ref(null);
const requireConversationForModal = ref(true);
const showScheduledMessagesDrawer = ref(false);
const showAdvancedFilters = ref(false);
const scheduledMessagesConversationFilter = ref(null);
const scheduledMessagesRefreshToken = ref(0);
const scheduledMessageToCancel = ref(null);
const cancelDialogRef = ref(null);

const currentAccountId = computed(() =>
  Number(store.getters.getCurrentAccountId || route.params.accountId || 0)
);

const currentUserId = computed(() =>
  Number(store.getters.getCurrentUser?.id || 0)
);

const advancedFiltersStorageKey = computed(
  () =>
    `kanban:advanced-filters:${currentAccountId.value || 'account'}:${currentUserId.value || 'user'}`
);

const stages = computed(() => {
  if (!activeFunnelId.value) return [];
  return store.getters['kanban/getFunnelStages'](activeFunnelId.value) || [];
});

const allLabels = computed(() => {
  const labels = store.getters['labels/getLabels'];
  if (!Array.isArray(labels)) return [];
  return labels
    .filter(label => label?.id)
    .sort((a, b) => (a.title || '').localeCompare(b.title || ''));
});

const allAgents = computed(() => {
  const agents = store.getters['agents/getAgents'];
  if (!Array.isArray(agents)) return [];
  return agents
    .filter(agent => agent?.id && agent?.confirmed)
    .sort((a, b) =>
      (a.name || a.email || '').localeCompare(b.name || b.email || '')
    );
});

const activeFunnelStagesCount = computed(() => stages.value.length);

const activeFunnelTotalItems = computed(() => {
  if (!activeFunnelId.value) return 0;

  return stages.value.reduce((total, stage) => {
    const items = store.getters['kanban/getFunnelItems'](
      activeFunnelId.value,
      stage.id
    );
    return total + (Array.isArray(items) ? items.length : 0);
  }, 0);
});

const scheduledMessagesPendingCount = computed(
  () =>
    scheduledMessages.value.filter(message => message.status === 'pending')
      .length
);

const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const statusFilterOptions = computed(() => [
  {
    value: 'all',
    label: t('KANBAN.FILTERS.STATUS.ALL'),
  },
  {
    value: 'open',
    label: t('KANBAN.STATUS.OPEN'),
  },
  {
    value: 'pending',
    label: t('KANBAN.STATUS.PENDING'),
  },
  {
    value: 'snoozed',
    label: t('KANBAN.STATUS.SNOOZED'),
  },
]);

const funnelOptions = computed(() => [
  {
    value: '',
    label: t('KANBAN.SELECT_FUNNEL'),
    disabled: true,
  },
  ...funnels.value.map(funnel => ({
    value: String(funnel.id),
    label: funnel.name,
  })),
]);

const stageFilterOptions = computed(() => [
  {
    value: '',
    label: t('KANBAN.FILTERS.ALL_STAGES'),
  },
  ...stages.value.map(stage => ({
    value: String(stage.id),
    label: stage.name,
  })),
]);

const labelFilterOptions = computed(() => [
  {
    value: '',
    label: t('KANBAN.FILTERS.ALL_LABELS'),
  },
  ...allLabels.value.map(label => ({
    value: String(label.id),
    label: label.title,
  })),
]);

const assigneeFilterOptions = computed(() => [
  {
    value: '',
    label: t('KANBAN.FILTERS.ALL_AGENTS'),
  },
  ...allAgents.value.map(agent => ({
    value: String(agent.id),
    label: agent.name || agent.email,
  })),
]);

const searchFilter = computed({
  get() {
    return viewFilters.value?.query || '';
  },
  set(value) {
    store.dispatch('kanban/setViewFilters', { query: value || '' });
  },
});

const stageFilter = computed({
  get() {
    const [selectedStageId] = viewFilters.value?.stageIds || [];
    return selectedStageId ? String(selectedStageId) : '';
  },
  set(value) {
    store.dispatch('kanban/setViewFilters', {
      stageIds: value ? [Number(value)] : [],
    });
  },
});

const labelFilter = computed({
  get() {
    const [selectedLabelId] = viewFilters.value?.labelIds || [];
    return selectedLabelId ? String(selectedLabelId) : '';
  },
  set(value) {
    store.dispatch('kanban/setViewFilters', {
      labelIds: value ? [Number(value)] : [],
    });
  },
});

const assigneeFilter = computed({
  get() {
    const assigneeId = viewFilters.value?.assigneeId;
    return assigneeId ? String(assigneeId) : '';
  },
  set(value) {
    store.dispatch('kanban/setViewFilters', {
      assigneeId: value ? Number(value) : null,
    });
  },
});

const statusFilter = computed({
  get() {
    return viewFilters.value?.status || 'all';
  },
  set(value) {
    store.dispatch('kanban/setViewFilters', { status: value || 'all' });
  },
});

const hasActiveFilters = computed(() => {
  const filters = viewFilters.value || {};
  return Boolean(
    (filters.query || '').trim() ||
      (filters.stageIds || []).length ||
      (filters.labelIds || []).length ||
      filters.assigneeId ||
      (filters.status || 'all') !== 'all'
  );
});

const activeFiltersCount = computed(() => {
  const filters = viewFilters.value || {};
  let count = 0;
  if ((filters.query || '').trim()) count += 1;
  if ((filters.stageIds || []).length) count += 1;
  if ((filters.labelIds || []).length) count += 1;
  if (filters.assigneeId) count += 1;
  if ((filters.status || 'all') !== 'all') count += 1;
  return count;
});

const advancedFiltersCount = computed(() => {
  const filters = viewFilters.value || {};
  let count = 0;
  if ((filters.stageIds || []).length) count += 1;
  if ((filters.labelIds || []).length) count += 1;
  if (filters.assigneeId) count += 1;
  if ((filters.status || 'all') !== 'all') count += 1;
  return count;
});

const loadFilterAuxiliaryData = async () => {
  const tasks = [];

  if (!allLabels.value.length) {
    tasks.push(store.dispatch('labels/get'));
  }

  if (!allAgents.value.length) {
    tasks.push(store.dispatch('agents/get'));
  }

  if (tasks.length) {
    await Promise.allSettled(tasks);
  }
};

const getConversationFromStore = conversationId => {
  if (!conversationId || !getConversationById.value) return null;
  return getConversationById.value(Number(conversationId));
};

const bootstrapActiveView = async ({ force = false } = {}) => {
  if (!activeFunnelId.value) return;

  await store.dispatch('kanban/bootstrapView', {
    view: viewMode.value,
    funnelId: activeFunnelId.value,
    force,
  });
};

const navigateToFunnelIfRequired = async funnelId => {
  const currentRouteFunnelId = Number(route.params.funnelId);
  if (
    Number.isNaN(currentRouteFunnelId) ||
    currentRouteFunnelId !== Number(funnelId)
  ) {
    await router.replace({
      name: 'kanban_funnel',
      params: { funnelId },
    });
  }
};

const initializeFunnelContext = async () => {
  await store.dispatch('kanban/fetchFunnels');
  const availableFunnels = funnels.value;
  if (!availableFunnels.length) return;

  const routeFunnelId = Number(route.params.funnelId);
  const targetFunnel =
    availableFunnels.find(funnel => funnel.id === routeFunnelId) ||
    availableFunnels[0];

  await store.dispatch('kanban/setActiveFunnelId', targetFunnel.id);
  await store.dispatch('kanban/fetchFunnelStages', targetFunnel.id);
  await loadFilterAuxiliaryData();
  await navigateToFunnelIfRequired(targetFunnel.id);
  await bootstrapActiveView({ force: true });
};

const handleFunnelSelect = async funnelId => {
  const selectedId = Number(funnelId);
  if (!selectedId || selectedId === activeFunnelId.value) return;

  await store.dispatch('kanban/setActiveFunnelId', selectedId);
  await store.dispatch('kanban/fetchFunnelStages', selectedId);
  await loadFilterAuxiliaryData();
  await bootstrapActiveView({ force: true });
  await router.push({
    name: 'kanban_funnel',
    params: { funnelId: selectedId },
  });
};

const funnelFilter = computed({
  get() {
    return activeFunnelId.value ? String(activeFunnelId.value) : '';
  },
  set(value) {
    if (!value) return;
    handleFunnelSelect(Number(value));
  },
});

const handleCreateFunnel = () => {
  selectedFunnel.value = null;
  showFunnelForm.value = true;
};

const handleEditFunnel = funnel => {
  selectedFunnel.value = funnel;
  showFunnelForm.value = true;
};

const handleFunnelSaved = async () => {
  await store.dispatch('kanban/fetchFunnels');
  const updatedFunnels = store.getters['kanban/getFunnels'];
  if (!updatedFunnels.length) {
    showFunnelForm.value = false;
    selectedFunnel.value = null;
    return;
  }

  const targetFunnel = selectedFunnel.value
    ? updatedFunnels.find(funnel => funnel.id === selectedFunnel.value.id)
    : updatedFunnels[updatedFunnels.length - 1];
  if (targetFunnel) {
    await handleFunnelSelect(targetFunnel.id);
  }

  showFunnelForm.value = false;
  selectedFunnel.value = null;
};

const handleScheduleMessage = conversation => {
  selectedScheduledMessage.value = null;
  selectedConversation.value = conversation;
  selectedDate.value = null;
  requireConversationForModal.value = true;
  showScheduledMessageForm.value = true;
};

const handleCreateScheduledMessageFromCalendar = date => {
  selectedScheduledMessage.value = null;
  selectedConversation.value = null;
  selectedDate.value = date;
  requireConversationForModal.value = false;
  showScheduledMessageForm.value = true;
};

const refreshScheduledMessages = () => {
  scheduledMessagesRefreshToken.value += 1;
  return store.dispatch('kanban/refreshPendingStatuses', {
    status: 'all',
  });
};

const handleScheduledMessageSaved = async () => {
  showScheduledMessageForm.value = false;
  selectedConversation.value = null;
  selectedScheduledMessage.value = null;
  selectedDate.value = null;
  await refreshScheduledMessages();
};

const closeScheduledMessageForm = () => {
  showScheduledMessageForm.value = false;
  selectedConversation.value = null;
  selectedScheduledMessage.value = null;
  selectedDate.value = null;
};

const openScheduledMessagesDrawer = payload => {
  const conversationId =
    typeof payload === 'object'
      ? payload?.conversationId ||
        payload?.conversation_id ||
        payload?.id ||
        null
      : payload;

  scheduledMessagesConversationFilter.value = conversationId
    ? Number(conversationId)
    : null;
  showScheduledMessagesDrawer.value = true;
};

const handleEditScheduledMessage = message => {
  showScheduledMessagesDrawer.value = false;
  selectedScheduledMessage.value = message;
  selectedConversation.value = getConversationFromStore(message.conversationId);
  selectedDate.value = null;
  requireConversationForModal.value = false;
  showScheduledMessageForm.value = true;
};

const handleCancelScheduledMessage = message => {
  if (message.status !== 'pending') return;
  scheduledMessageToCancel.value = message;
};

const confirmCancelScheduledMessage = async () => {
  if (!scheduledMessageToCancel.value?.id) return;

  try {
    await store.dispatch(
      'kanban/deleteScheduledMessage',
      scheduledMessageToCancel.value.id
    );
    await refreshScheduledMessages();
    scheduledMessageToCancel.value = null;
  } catch (_) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CANCEL_ERROR'));
  }
};

const closeCancelDialog = () => {
  scheduledMessageToCancel.value = null;
};

const clearFilters = () => {
  store.dispatch('kanban/resetViewFilters');
};

const toggleAdvancedFilters = () => {
  showAdvancedFilters.value = !showAdvancedFilters.value;
};

const setViewMode = async mode => {
  if (mode === viewMode.value) return;
  await store.dispatch('kanban/setViewMode', mode);
};

watch(scheduledMessageToCancel, async value => {
  if (!value) return;
  await nextTick();
  cancelDialogRef.value?.open?.();
});

watch(
  () => route.params.funnelId,
  async newFunnelId => {
    const parsedFunnelId = Number(newFunnelId);
    if (!parsedFunnelId || parsedFunnelId === activeFunnelId.value) return;
    const targetFunnel = funnels.value.find(
      funnel => funnel.id === parsedFunnelId
    );
    if (!targetFunnel) return;

    await store.dispatch('kanban/setActiveFunnelId', parsedFunnelId);
    await store.dispatch('kanban/fetchFunnelStages', parsedFunnelId);
    await loadFilterAuxiliaryData();
    await bootstrapActiveView({ force: true });
  }
);

watch(
  () => viewMode.value,
  async () => {
    await bootstrapActiveView();
  }
);

watch(
  () => advancedFiltersStorageKey.value,
  storageKey => {
    if (typeof window === 'undefined') return;
    if (!storageKey) return;
    const savedValue = window.localStorage.getItem(storageKey);
    showAdvancedFilters.value = savedValue === '1';
  },
  { immediate: true }
);

watch(showAdvancedFilters, value => {
  if (typeof window === 'undefined') return;
  const storageKey = advancedFiltersStorageKey.value;
  if (!storageKey) return;

  if (value) {
    window.localStorage.setItem(storageKey, '1');
  } else {
    window.localStorage.removeItem(storageKey);
  }
});

onMounted(async () => {
  if (!viewMode.value) {
    await store.dispatch('kanban/setViewMode', 'kanban');
  }
  await initializeFunnelContext();
});
</script>

<template>
  <div class="kanban-container flex flex-col overflow-hidden">
    <div
      class="kanban-header flex flex-col border-b border-n-weak bg-n-solid-2 px-5 py-4 gap-4"
    >
      <div class="flex flex-wrap items-center gap-3 justify-between">
        <div class="flex items-center gap-3 min-w-0">
          <div
            class="flex items-center justify-center size-9 rounded-lg bg-n-solid-3 border border-n-weak"
          >
            <Icon icon="i-lucide-layout-grid" class="size-4 text-n-slate-11" />
          </div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('KANBAN.TITLE') }}
          </h1>

          <div
            v-if="activeFunnel"
            class="hidden md:flex items-center gap-2 ml-2"
          >
            <span
              class="inline-flex items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-2.5 py-1 text-xs text-n-slate-11"
            >
              <Icon icon="i-lucide-columns-3" class="size-3.5" />
              {{ activeFunnelStagesCount }} {{ t('KANBAN.STAGES.TITLE') }}
            </span>
            <span
              class="inline-flex items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-2.5 py-1 text-xs text-n-slate-11"
            >
              <Icon icon="i-lucide-message-square" class="size-3.5" />
              {{ activeFunnelTotalItems }} {{ t('KANBAN.FILTERS.ITEMS') }}
            </span>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <div
            class="flex gap-1 rounded-lg border border-n-weak bg-n-solid-3 p-1"
          >
            <Button
              :variant="viewMode === 'kanban' ? 'solid' : 'ghost'"
              size="sm"
              icon="i-lucide-layout-grid"
              :title="t('KANBAN.VIEWS.KANBAN')"
              @click="setViewMode('kanban')"
            />
            <Button
              :variant="viewMode === 'list' ? 'solid' : 'ghost'"
              size="sm"
              icon="i-lucide-list"
              :title="t('KANBAN.VIEWS.LIST')"
              @click="setViewMode('list')"
            />
            <Button
              :variant="viewMode === 'calendar' ? 'solid' : 'ghost'"
              size="sm"
              icon="i-lucide-calendar"
              :title="t('KANBAN.VIEWS.CALENDAR')"
              @click="setViewMode('calendar')"
            />
          </div>

          <Button
            variant="ghost"
            size="sm"
            icon="i-lucide-clock-3"
            :title="t('KANBAN.SCHEDULED_MESSAGES.DRAWER_TITLE')"
            @click="openScheduledMessagesDrawer()"
          >
            <span class="ml-2 hidden lg:inline">
              {{ t('KANBAN.SCHEDULED_MESSAGES.DRAWER_TRIGGER') }}
            </span>
            <span
              v-if="scheduledMessagesPendingCount > 0"
              class="ml-2 inline-flex items-center justify-center min-w-5 h-5 px-1.5 rounded-full bg-n-blue-9 text-white text-[11px] font-semibold"
            >
              {{ scheduledMessagesPendingCount }}
            </span>
          </Button>

          <Button
            v-if="activeFunnel"
            variant="ghost"
            size="sm"
            icon="i-lucide-edit"
            :title="t('KANBAN.FUNNELS.EDIT')"
            @click="handleEditFunnel(activeFunnel)"
          />
          <Button
            color="blue"
            size="sm"
            icon="i-lucide-plus"
            :title="t('KANBAN.FUNNELS.CREATE')"
            @click="handleCreateFunnel"
          />
        </div>
      </div>

      <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3 shadow-sm">
        <div
          class="kanban-filter-grid grid grid-cols-1 items-start gap-3 lg:grid-cols-[minmax(260px,1fr)_minmax(220px,280px)_auto_auto]"
        >
          <div class="kanban-filter-group">
            <label class="kanban-filter-label">
              {{ t('KANBAN.FILTERS.SEARCH_LABEL') }}
            </label>
            <Input
              v-model="searchFilter"
              type="search"
              :placeholder="t('KANBAN.FILTERS.SEARCH_PLACEHOLDER')"
              :custom-input-class="[
                'h-10 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 ltr:!pl-8 !py-1 rtl:!pr-8',
              ]"
              class="w-full"
            >
              <template #prefix>
                <Icon
                  icon="i-lucide-search"
                  class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
                />
              </template>
            </Input>
          </div>

          <div class="kanban-filter-group kanban-funnel-filter-group">
            <label class="kanban-filter-label">
              {{ t('KANBAN.FILTERS.FUNNEL') }}
            </label>
            <KanbanFilterSelect
              v-model="funnelFilter"
              :options="funnelOptions"
              :placeholder="t('KANBAN.SELECT_FUNNEL')"
            />
          </div>

          <Button
            data-testid="kanban-advanced-filters-toggle"
            variant="ghost"
            size="sm"
            icon="i-lucide-sliders-horizontal"
            class="kanban-filter-action kanban-advanced-filters-toggle-btn !h-10 lg:w-auto"
            :title="
              showAdvancedFilters
                ? t('KANBAN.FILTERS.ADVANCED_HIDE')
                : t('KANBAN.FILTERS.ADVANCED_SHOW')
            "
            @click="toggleAdvancedFilters"
          >
            <span class="ml-2">{{ t('KANBAN.FILTERS.ADVANCED') }}</span>
            <span
              v-if="advancedFiltersCount > 0"
              data-testid="kanban-advanced-filters-count"
              class="ml-2 inline-flex min-w-5 items-center justify-center rounded-full bg-n-blue-9 px-1.5 text-[11px] font-semibold text-white"
            >
              {{ advancedFiltersCount }}
            </span>
          </Button>

          <Button
            v-if="hasActiveFilters"
            variant="ghost"
            size="sm"
            icon="i-lucide-filter-x"
            class="kanban-filter-action !h-10 lg:w-auto"
            :title="t('KANBAN.FILTERS.CLEAR')"
            @click="clearFilters"
          >
            <span class="ml-2">{{ t('KANBAN.FILTERS.CLEAR') }}</span>
          </Button>
        </div>

        <div
          v-if="showAdvancedFilters"
          data-testid="kanban-advanced-filters-panel"
          class="mt-3 rounded-lg border border-n-weak bg-n-solid-2 p-3"
        >
          <div class="mb-2 flex items-center justify-between">
            <h2
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('KANBAN.FILTERS.ADVANCED') }}
            </h2>
            <span
              v-if="hasActiveFilters"
              class="inline-flex items-center rounded-full border border-n-weak bg-n-solid-3 px-2 py-0.5 text-[11px] font-semibold text-n-slate-10"
            >
              {{
                t('KANBAN.FILTERS.ACTIVE_COUNT', { count: activeFiltersCount })
              }}
            </span>
          </div>

          <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
            <div class="kanban-filter-group">
              <label class="kanban-filter-label">
                {{ t('KANBAN.FILTERS.STATUS_LABEL') }}
              </label>
              <KanbanFilterSelect
                v-model="statusFilter"
                :options="statusFilterOptions"
                :placeholder="t('KANBAN.FILTERS.STATUS.ALL')"
              />
            </div>

            <div class="kanban-filter-group">
              <label class="kanban-filter-label">
                {{ t('KANBAN.FILTERS.STAGE') }}
              </label>
              <KanbanFilterSelect
                v-model="stageFilter"
                :options="stageFilterOptions"
                :placeholder="t('KANBAN.FILTERS.ALL_STAGES')"
              />
            </div>

            <div class="kanban-filter-group">
              <label class="kanban-filter-label">
                {{ t('KANBAN.FILTERS.LABEL') }}
              </label>
              <KanbanFilterSelect
                v-model="labelFilter"
                :options="labelFilterOptions"
                :placeholder="t('KANBAN.FILTERS.ALL_LABELS')"
              />
            </div>

            <div class="kanban-filter-group">
              <label class="kanban-filter-label">
                {{ t('KANBAN.FILTERS.ASSIGNEE') }}
              </label>
              <KanbanFilterSelect
                v-model="assigneeFilter"
                :options="assigneeFilterOptions"
                :placeholder="t('KANBAN.FILTERS.ALL_AGENTS')"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="kanban-content flex-1 min-h-0 overflow-hidden bg-n-background">
      <div
        v-if="!activeFunnelId && funnels.length === 0"
        class="flex h-full flex-col items-center justify-center px-6 text-center"
      >
        <div
          class="mb-6 flex items-center justify-center rounded-2xl border border-n-weak bg-n-solid-2 p-6"
        >
          <Icon icon="i-lucide-layout-grid" class="size-10 text-n-slate-10" />
        </div>
        <h2 class="text-2xl font-semibold text-n-slate-12">
          {{ t('KANBAN.FUNNELS.NO_FUNNELS') }}
        </h2>
        <p class="mt-2 max-w-lg text-sm text-n-slate-10">
          {{ t('KANBAN.FUNNELS.NO_FUNNELS_DESCRIPTION') }}
        </p>
        <Button
          icon="i-lucide-plus"
          color="blue"
          class="mt-6"
          @click="handleCreateFunnel"
        >
          <span class="ml-2">{{ t('KANBAN.FUNNELS.CREATE') }}</span>
        </Button>
      </div>

      <div
        v-else-if="!activeFunnelId"
        class="flex h-full items-center justify-center text-sm text-n-slate-10"
      >
        {{ t('KANBAN.SELECT_FUNNEL') }}
      </div>

      <template v-else>
        <KanbanBoard
          v-if="viewMode === 'kanban'"
          :key="`kanban-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
        />

        <ListView
          v-else-if="viewMode === 'list'"
          :key="`list-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
          @manage-scheduled="openScheduledMessagesDrawer"
        />

        <CalendarView
          v-else-if="viewMode === 'calendar'"
          :key="`calendar-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
          @create-scheduled-message="handleCreateScheduledMessageFromCalendar"
          @edit-scheduled-message="handleEditScheduledMessage"
          @cancel-scheduled-message="handleCancelScheduledMessage"
        />
      </template>
    </div>

    <FunnelForm
      :show="showFunnelForm"
      :funnel="selectedFunnel"
      @close="showFunnelForm = false"
      @saved="handleFunnelSaved"
    />

    <ScheduledMessageForm
      :show="showScheduledMessageForm"
      :conversation="selectedConversation"
      :scheduled-message="selectedScheduledMessage"
      :require-conversation="requireConversationForModal"
      :funnel-id="activeFunnelId"
      :selected-date="selectedDate"
      @close="closeScheduledMessageForm"
      @saved="handleScheduledMessageSaved"
    />

    <ScheduledMessagesDrawer
      :show="showScheduledMessagesDrawer"
      :refresh-token="scheduledMessagesRefreshToken"
      :initial-conversation-id="scheduledMessagesConversationFilter"
      @close="showScheduledMessagesDrawer = false"
      @edit-scheduled-message="handleEditScheduledMessage"
      @cancelled="refreshScheduledMessages"
    />

    <Dialog
      v-if="scheduledMessageToCancel"
      ref="cancelDialogRef"
      :title="t('KANBAN.SCHEDULED_MESSAGES.CANCEL_CONFIRM_TITLE')"
      :description="t('KANBAN.SCHEDULED_MESSAGES.CANCEL_CONFIRM_MESSAGE')"
      :confirm-button-label="t('KANBAN.SCHEDULED_MESSAGES.CANCEL')"
      type="alert"
      @close="closeCancelDialog"
      @confirm="confirmCancelScheduledMessage"
    />
  </div>
</template>

<style scoped>
.kanban-container {
  height: 100%;
  width: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.kanban-filter-grid {
  align-items: start;
}

.kanban-filter-group {
  min-width: 0;
}

.kanban-funnel-filter-group {
  transform: translateY(-2px);
}

.kanban-filter-label {
  margin-bottom: 0.375rem;
  display: block;
  font-size: 0.75rem;
  font-weight: 600;
  line-height: 1.2;
  color: rgb(var(--slate-10));
}

.kanban-filter-action {
  align-self: end;
}

.kanban-advanced-filters-toggle-btn {
  transform: translateY(-2px);
}
</style>
