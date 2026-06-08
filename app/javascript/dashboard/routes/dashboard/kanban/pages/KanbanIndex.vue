<script setup>
// KanbanIndex redesenhado (P1-01). Página-mãe que orquestra:
//   - Novo header (KanbanHeader / KanbanViewSwitch / KanbanFunnelSelect)
//   - View atual (KanbanBoard | ListView | CalendarView)
//   - Empty state (KanbanEmptyState — P1-09)
//   - Drawers: FunnelForm, ScheduledMessageForm, ScheduledMessagesDrawer
//   - KanbanFilterSelect (painel de filtros — abre/fecha)
//
// State da view é Pinia (useKanbanFiltersStore, persistido em localStorage).
// Funnels/stages/scheduled messages: Vuex mantido (migração incremental).
import { onMounted, computed, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';

import KanbanBoard from 'dashboard/components-next/Kanban/KanbanBoard.vue';
import ListView from 'dashboard/components-next/Kanban/ListView.vue';
import CalendarView from 'dashboard/components-next/ScheduledMessages/CalendarView.vue';
import KanbanHeader from 'dashboard/components-next/Kanban/KanbanHeader.vue';
import KanbanEmptyState from 'dashboard/components-next/Kanban/KanbanEmptyState.vue';
import KanbanSnackbar from 'dashboard/components-next/Kanban/KanbanSnackbar.vue';
import KanbanShortcutsHelp from 'dashboard/components-next/Kanban/KanbanShortcutsHelp.vue';
import KanbanTemplatePicker from 'dashboard/components-next/Kanban/KanbanTemplatePicker.vue';
import KanbanMetrics from 'dashboard/components-next/Kanban/KanbanMetrics.vue';
import KanbanSavedViews from 'dashboard/components-next/Kanban/KanbanSavedViews.vue';
import KanbanCardDrawer from 'dashboard/components-next/Kanban/KanbanCardDrawer.vue';
import KanbanWonLostModal from 'dashboard/components-next/Kanban/KanbanWonLostModal.vue';
import KanbanBulkActionBar from 'dashboard/components-next/Kanban/KanbanBulkActionBar.vue';
import FunnelForm from 'dashboard/components-next/Kanban/FunnelForm.vue';
import KanbanAutomationsManager from 'dashboard/components-next/Kanban/KanbanAutomationsManager.vue';
import KanbanDailySummarySettings from 'dashboard/components-next/Kanban/KanbanDailySummarySettings.vue';
import ScheduledMessageForm from 'dashboard/components-next/ScheduledMessages/ScheduledMessageForm.vue';
import ScheduledMessagesDrawer from 'dashboard/components-next/ScheduledMessages/ScheduledMessagesDrawer.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import { useKanbanFiltersStore } from 'dashboard/store/pinia/kanban/filters';
import { useKanbanShortcuts } from 'dashboard/composables/kanban/useKanbanShortcuts';
import { useKanbanUrlFilters } from 'dashboard/composables/kanban/useKanbanUrlFilters';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const filtersStore = useKanbanFiltersStore();
const { viewMode, filtersOpen, hasActiveFilters } = storeToRefs(filtersStore);

// KANBAN-P2-04: filtros <-> URL.
useKanbanUrlFilters();

const funnels = computed(() => store.getters['kanban/getFunnels']);
const activeFunnelId = computed(
  () => store.getters['kanban/getActiveFunnelId']
);
const viewFilters = computed(() => store.getters['kanban/getViewFilters']);
const scheduledMessages = computed(
  () => store.getters['kanban/getScheduledMessages']
);
const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const showFunnelForm = ref(false);
const showTemplatePicker = ref(false);
const showScheduledMessageForm = ref(false);

// P2-03 drawer
const drawerOpen = ref(false);
const drawerConversationId = ref(null);

// P2-06 won/lost
const wonLostMode = ref(null); // 'won' | 'lost' | null
const wonLostItem = ref(null);

// P2-07 bulk
const bulkMode = ref(false);

const handleOpenDrawer = item => {
  const cid =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;
  if (!cid) return;
  drawerConversationId.value = Number(cid);
  drawerOpen.value = true;
};

const handleWonLost = ({ item, mode }) => {
  wonLostItem.value = item;
  wonLostMode.value = mode;
};

const handleWonLostSaved = () => {
  wonLostItem.value = null;
  wonLostMode.value = null;
};

const handleWonLostSkip = () => {
  wonLostItem.value = null;
  wonLostMode.value = null;
};

const toggleBulkMode = () => {
  bulkMode.value = !bulkMode.value;
};
const selectedFunnel = ref(null);
const selectedConversation = ref(null);
const selectedScheduledMessage = ref(null);
const selectedDate = ref(null);
const requireConversationForModal = ref(true);
const showScheduledMessagesDrawer = ref(false);
const scheduledMessagesConversationFilter = ref(null);
const scheduledMessagesRefreshToken = ref(0);
const scheduledMessageToCancel = ref(null);
const cancelDialogRef = ref(null);
const showShortcutsHelp = ref(false);

// KANBAN-P3 GAP-FIX: modais Automações + Resumo Diário (rotas-as-modal).
const showAutomationsModal = ref(false);
const showDailySummaryModal = ref(false);
const activeFunnel = computed(() =>
  funnels.value.find(f => f.id === activeFunnelId.value)
);
const activeFunnelStages = computed(() =>
  activeFunnelId.value
    ? store.getters['kanban/getFunnelStages'](activeFunnelId.value) || []
    : []
);
const openAutomationsModal = () => {
  if (!activeFunnelId.value) return;
  showAutomationsModal.value = true;
};
const openDailySummaryModal = () => {
  if (!activeFunnelId.value) return;
  showDailySummaryModal.value = true;
};

const scheduledPendingCount = computed(
  () => scheduledMessages.value.filter(m => m.status === 'pending').length
);

const itemCountsByFunnel = computed(() => {
  const map = {};
  funnels.value.forEach(f => {
    const fs = store.getters['kanban/getFunnelStages'](f.id) || [];
    let count = 0;
    fs.forEach(s => {
      const items = store.getters['kanban/getFunnelItems'](f.id, s.id);
      count += Array.isArray(items) ? items.length : 0;
    });
    map[f.id] = count;
  });
  return map;
});

const bootstrapActiveView = async ({ force = false } = {}) => {
  if (!activeFunnelId.value) return;
  await store.dispatch('kanban/bootstrapView', {
    view: viewMode.value,
    funnelId: activeFunnelId.value,
    force,
  });
};

const navigateToFunnelIfRequired = async funnelId => {
  const current = Number(route.params.funnelId);
  if (Number.isNaN(current) || current !== Number(funnelId)) {
    await router.replace({ name: 'kanban_funnel', params: { funnelId } });
  }
};

const loadAuxiliaryData = async () => {
  const tasks = [];
  if (!store.getters['labels/getLabels']?.length)
    tasks.push(store.dispatch('labels/get'));
  if (!store.getters['agents/getAgents']?.length)
    tasks.push(store.dispatch('agents/get'));
  if (tasks.length) await Promise.allSettled(tasks);
};

const handleFunnelSelect = async funnelId => {
  const selectedId = Number(funnelId);
  if (!selectedId || selectedId === activeFunnelId.value) return;
  await store.dispatch('kanban/setActiveFunnelId', selectedId);
  await store.dispatch('kanban/fetchFunnelStages', selectedId);
  await loadAuxiliaryData();
  await bootstrapActiveView({ force: true });
  await router.push({
    name: 'kanban_funnel',
    params: { funnelId: selectedId },
  });
};

const initializeFunnelContext = async () => {
  await store.dispatch('kanban/fetchFunnels');
  const available = funnels.value;
  if (!available.length) return;
  const routeFunnelId = Number(route.params.funnelId);
  const target = available.find(f => f.id === routeFunnelId) || available[0];
  await store.dispatch('kanban/setActiveFunnelId', target.id);
  await store.dispatch('kanban/fetchFunnelStages', target.id);
  await loadAuxiliaryData();
  await navigateToFunnelIfRequired(target.id);
  await bootstrapActiveView({ force: true });
};

const handleCreateFunnel = () => {
  // P2-01: abre galeria de templates primeiro (pode escolher "Em branco" pra ir pro form).
  showTemplatePicker.value = true;
};

const handleOpenBlankFunnel = () => {
  selectedFunnel.value = null;
  showFunnelForm.value = true;
};

const handleTemplateApplied = async kanban => {
  await store.dispatch('kanban/fetchFunnels');
  if (kanban?.id) await handleFunnelSelect(kanban.id);
};

// P1-12: atalhos de teclado
useKanbanShortcuts({
  onNewFunnel: handleCreateFunnel,
  onHelp: () => {
    showShortcutsHelp.value = true;
  },
  onEsc: () => {
    if (showShortcutsHelp.value) showShortcutsHelp.value = false;
    else if (showFunnelForm.value) showFunnelForm.value = false;
    else if (showScheduledMessagesDrawer.value)
      showScheduledMessagesDrawer.value = false;
  },
});

const handleFunnelSaved = async () => {
  await store.dispatch('kanban/fetchFunnels');
  const updated = store.getters['kanban/getFunnels'];
  if (!updated.length) {
    showFunnelForm.value = false;
    selectedFunnel.value = null;
    return;
  }
  const target = selectedFunnel.value
    ? updated.find(f => f.id === selectedFunnel.value.id)
    : updated[updated.length - 1];
  if (target) await handleFunnelSelect(target.id);
  showFunnelForm.value = false;
  selectedFunnel.value = null;
};

const getConversationFromStore = id => {
  if (!id || !getConversationById.value) return null;
  return getConversationById.value(Number(id));
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
  return store.dispatch('kanban/refreshPendingStatuses', { status: 'all' });
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
  const id =
    typeof payload === 'object'
      ? payload?.conversationId ||
        payload?.conversation_id ||
        payload?.id ||
        null
      : payload;
  scheduledMessagesConversationFilter.value = id ? Number(id) : null;
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

const setViewMode = mode => {
  if (mode === viewMode.value) return;
  filtersStore.setViewMode(mode);
  // mantemos sync com Vuex enquanto consumers antigos existirem
  store.dispatch('kanban/setViewMode', mode);
};

watch(scheduledMessageToCancel, async value => {
  if (!value) return;
  await nextTick();
  cancelDialogRef.value?.open?.();
});

watch(
  () => route.params.funnelId,
  async newId => {
    const parsed = Number(newId);
    if (!parsed || parsed === activeFunnelId.value) return;
    if (!funnels.value.find(f => f.id === parsed)) return;
    await store.dispatch('kanban/setActiveFunnelId', parsed);
    await store.dispatch('kanban/fetchFunnelStages', parsed);
    await loadAuxiliaryData();
    await bootstrapActiveView({ force: true });
  }
);

watch(viewMode, () => bootstrapActiveView());

// KANBAN-P3 GAP-FIX: abre modais ao acessar rota /:funnelId/automations | /daily-summary
const syncModalsFromRoute = () => {
  showAutomationsModal.value = route.name === 'kanban_automations';
  showDailySummaryModal.value = route.name === 'kanban_daily_summary';
};
watch(
  () => route.name,
  () => syncModalsFromRoute()
);

onMounted(async () => {
  // sync viewMode persistido em Pinia → Vuex (consumer antigo)
  store.dispatch('kanban/setViewMode', viewMode.value);
  await initializeFunnelContext();
  syncModalsFromRoute();
});
</script>

<template>
  <div
    class="flex flex-col h-full w-full overflow-hidden bg-slate-50 dark:bg-n-solid-1"
  >
    <KanbanHeader
      :funnels="funnels"
      :funnel-id="activeFunnelId"
      :item-counts="itemCountsByFunnel"
      :view-mode="viewMode"
      :has-active-filters="hasActiveFilters"
      :scheduled-count="scheduledPendingCount"
      :bulk-mode="bulkMode"
      @update:funnel-id="handleFunnelSelect"
      @update:view-mode="setViewMode"
      @new-funnel="handleCreateFunnel"
      @toggle-filters="filtersStore.toggleFilters()"
      @toggle-scheduled="showScheduledMessagesDrawer = true"
      @toggle-bulk="toggleBulkMode"
      @shortcuts="showShortcutsHelp = true"
      @open-automations="openAutomationsModal"
      @open-daily-summary="openDailySummaryModal"
    >
      <template #metrics>
        <div v-if="activeFunnelId" class="flex items-center gap-3">
          <KanbanMetrics :funnel-id="activeFunnelId" />
          <KanbanSavedViews :funnel-id="activeFunnelId" />
        </div>
      </template>
    </KanbanHeader>

    <div
      v-if="filtersOpen"
      class="border-b border-slate-200 dark:border-slate-800 bg-white dark:bg-n-solid-1 px-4 py-3"
    >
      <input
        type="search"
        class="w-full max-w-md px-3 h-9 rounded-lg bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-700 text-sm text-slate-800 dark:text-slate-100 focus:border-iris-500 focus:outline-none"
        :placeholder="t('KANBAN.FILTERS.SEARCH_PLACEHOLDER')"
        :value="viewFilters?.query || ''"
        @input="
          e =>
            store.dispatch('kanban/setViewFilters', { query: e.target.value })
        "
      />
    </div>

    <div class="flex-1 min-h-0 overflow-hidden">
      <KanbanEmptyState
        v-if="!funnels.length"
        variant="account"
        @create-blank="handleCreateFunnel"
        @open-templates="handleCreateFunnel"
        @open-demo="handleCreateFunnel"
      />

      <div
        v-else-if="!activeFunnelId"
        class="flex h-full items-center justify-center text-sm text-slate-500 dark:text-slate-400"
      >
        {{ t('KANBAN.SELECT_FUNNEL') }}
      </div>

      <template v-else>
        <KanbanBoard
          v-if="viewMode === 'kanban'"
          :key="`kanban-${activeFunnelId}`"
          :funnel-id="activeFunnelId"
          :bulk-mode="bulkMode"
          @schedule-message="handleScheduleMessage"
          @open-drawer="handleOpenDrawer"
          @won-lost="handleWonLost"
        />

        <ListView
          v-else-if="viewMode === 'list'"
          :key="`list-${activeFunnelId}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
          @manage-scheduled="openScheduledMessagesDrawer"
        />

        <CalendarView
          v-else-if="viewMode === 'calendar'"
          :key="`calendar-${activeFunnelId}`"
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

    <KanbanTemplatePicker
      :show="showTemplatePicker"
      @close="showTemplatePicker = false"
      @blank="handleOpenBlankFunnel"
      @applied="handleTemplateApplied"
    />

    <KanbanCardDrawer
      :show="drawerOpen"
      :conversation-id="drawerConversationId"
      @close="drawerOpen = false"
    />

    <KanbanWonLostModal
      :show="!!wonLostMode"
      :mode="wonLostMode || 'won'"
      :funnel-id="activeFunnelId"
      :item="wonLostItem"
      @saved="handleWonLostSaved"
      @skip="handleWonLostSkip"
    />

    <KanbanBulkActionBar
      v-if="bulkMode"
      :funnel-id="activeFunnelId"
      :stages="store.getters['kanban/getFunnelStages'](activeFunnelId) || []"
      @refreshed="
        store.dispatch('kanban/bootstrapView', {
          view: 'kanban',
          funnelId: activeFunnelId,
          force: true,
        })
      "
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

    <!-- KANBAN-P3 GAP-FIX: modal Automações (rota-as-modal /kanban/:funnelId/automations) -->
    <Teleport to="body">
      <div
        v-if="showAutomationsModal && activeFunnelId"
        class="fixed inset-0 z-[60] flex items-start justify-center bg-slate-900/40 dark:bg-black/60 backdrop-blur-sm px-4 py-10 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        @click.self="showAutomationsModal = false"
      >
        <div
          class="w-full max-w-3xl rounded-xl bg-white dark:bg-slate-900 shadow-xl border border-slate-200 dark:border-slate-700"
        >
          <header
            class="flex items-center justify-between px-4 py-3 border-b border-slate-200 dark:border-slate-700"
          >
            <h2 class="text-base font-semibold text-slate-900 dark:text-white">
              {{ t('KANBAN.AUTOMATIONS.NAV_LABEL') }}
            </h2>
            <button
              type="button"
              class="size-8 inline-flex items-center justify-center rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
              :aria-label="t('GENERAL_SETTINGS.CLOSE') || 'Close'"
              @click="showAutomationsModal = false"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </header>
          <div class="p-4">
            <KanbanAutomationsManager
              :funnel-id="activeFunnelId"
              :stages="activeFunnelStages"
            />
          </div>
        </div>
      </div>
    </Teleport>

    <!-- KANBAN-P3 GAP-FIX: modal Resumo Diário (rota-as-modal /kanban/:funnelId/daily-summary) -->
    <Teleport to="body">
      <div
        v-if="showDailySummaryModal && activeFunnelId"
        class="fixed inset-0 z-[60] flex items-start justify-center bg-slate-900/40 dark:bg-black/60 backdrop-blur-sm px-4 py-10 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        @click.self="showDailySummaryModal = false"
      >
        <div
          class="w-full max-w-2xl rounded-xl bg-white dark:bg-slate-900 shadow-xl border border-slate-200 dark:border-slate-700"
        >
          <header
            class="flex items-center justify-between px-4 py-3 border-b border-slate-200 dark:border-slate-700"
          >
            <h2 class="text-base font-semibold text-slate-900 dark:text-white">
              {{ t('KANBAN.DAILY_SUMMARY.NAV_LABEL') }}
            </h2>
            <button
              type="button"
              class="size-8 inline-flex items-center justify-center rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
              :aria-label="t('GENERAL_SETTINGS.CLOSE') || 'Close'"
              @click="showDailySummaryModal = false"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </header>
          <div class="p-4">
            <KanbanDailySummarySettings
              :funnel-id="activeFunnelId"
              :kanban="activeFunnel || {}"
            />
          </div>
        </div>
      </div>
    </Teleport>

    <KanbanSnackbar />

    <KanbanShortcutsHelp
      :show="showShortcutsHelp"
      @close="showShortcutsHelp = false"
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
