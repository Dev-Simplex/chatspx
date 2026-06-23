<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import KanbanColumn from './KanbanColumn.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import StageForm from './StageForm.vue';
import AddConversationModal from './AddConversationModal.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['itemMoved', 'scheduleMessage', 'removeItem']);

const store = useStore();
const { t } = useI18n();

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);
const isLoading = computed(() => store.getters['kanban/getUIFlags'].isFetching);
const viewFilters = computed(() => store.getters['kanban/getViewFilters']);
const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);
const getConversationLabels = computed(
  () => store.getters['conversationLabels/getConversationLabels']
);

const localStages = ref([]);
const showStageForm = ref(false);
const selectedStage = ref(null);
const movingItems = ref(new Set());

watch(
  () => stages.value,
  newStages => {
    if (Array.isArray(newStages)) {
      localStages.value = [...newStages];
    }
  },
  { immediate: true, deep: true }
);

const normalizeText = value => String(value || '').toLowerCase();

const extractAssigneeId = source => {
  if (!source) return null;

  return (
    source.assigneeId ||
    source.assignee_id ||
    source.assignee?.id ||
    source.assignee?.user?.id ||
    source.meta?.assignee?.id ||
    source.meta?.assignee_id ||
    null
  );
};

const resolveConversationKey = item => {
  const value =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;

  if (value == null) return null;
  return String(value);
};

const resolveConversationId = item => {
  const value =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;

  const normalized = Number(value);
  if (!Number.isNaN(normalized) && normalized > 0) {
    return normalized;
  }

  return null;
};

const getItemsForStage = stageId =>
  store.getters['kanban/getFunnelItems'](props.funnelId, stageId);

const conversations = computed(() => {
  const conversationMap = {};

  (stages.value || []).forEach(stage => {
    const stageItems = getItemsForStage(stage.id);

    stageItems.forEach(item => {
      const conversationKey = resolveConversationKey(item);
      if (!conversationKey || conversationMap[conversationKey]) return;

      const itemConversation = item.conversation || {};
      const conversationId = resolveConversationId(item);
      const storeConversation =
        conversationId && typeof getConversationById.value === 'function'
          ? getConversationById.value(conversationId)
          : null;

      const mergedConversation = {
        ...(storeConversation || {}),
        ...itemConversation,
      };

      const contactFromConversation =
        mergedConversation.contact ||
        storeConversation?.meta?.sender ||
        storeConversation?.contact ||
        {};

      conversationMap[conversationKey] = {
        ...mergedConversation,
        id: conversationId || mergedConversation.id || null,
        displayId:
          mergedConversation.displayId ||
          mergedConversation.display_id ||
          conversationId ||
          conversationKey,
        status: mergedConversation.status || 'open',
        assigneeId: extractAssigneeId(mergedConversation),
        contact: {
          ...contactFromConversation,
        },
      };
    });
  });

  return conversationMap;
});

const getItemConversation = item => {
  const key = resolveConversationKey(item);
  if (key && conversations.value[key]) {
    return conversations.value[key];
  }

  return item?.conversation || {};
};

const getItemLabels = item => {
  const conversationId = resolveConversationId(item);
  if (!conversationId || typeof getConversationLabels.value !== 'function') {
    return [];
  }

  const labels = getConversationLabels.value(conversationId);
  return Array.isArray(labels) ? labels : [];
};

const matchesQueryFilter = (item, query) => {
  if (!query) return true;

  const conversation = getItemConversation(item);
  const haystack = [
    conversation?.contact?.name,
    conversation?.contact?.phone_number,
    conversation?.contact?.phoneNumber,
    conversation?.displayId,
    conversation?.display_id,
    conversation?.lastMessage?.content,
    conversation?.lastMessage?.processed_message_content,
    conversation?.last_message?.content,
    conversation?.last_message?.processed_message_content,
  ]
    .map(normalizeText)
    .join(' ');

  return haystack.includes(query);
};

const matchesLabelFilter = item => {
  const labelIds = viewFilters.value?.labelIds || [];
  if (!labelIds.length) return true;

  const labelSet = new Set(labelIds.map(Number));
  return getItemLabels(item).some(label => labelSet.has(Number(label.id)));
};

const matchesAssigneeFilter = item => {
  const selectedAssigneeId = Number(viewFilters.value?.assigneeId || 0);
  if (!selectedAssigneeId) return true;

  const conversation = getItemConversation(item);
  const assigneeId =
    extractAssigneeId(item?.conversation) ||
    extractAssigneeId(conversation) ||
    null;

  return Number(assigneeId) === selectedAssigneeId;
};

const matchesStatusFilter = item => {
  const selectedStatus = viewFilters.value?.status || 'all';
  if (selectedStatus === 'all') return true;

  const conversation = getItemConversation(item);
  return (conversation?.status || 'open') === selectedStatus;
};

const matchesStageFilter = stageId => {
  const stageIds = viewFilters.value?.stageIds || [];
  if (!stageIds.length) return true;
  return stageIds.map(Number).includes(Number(stageId));
};

const isItemVisible = (item, stageId) => {
  if (!matchesStageFilter(stageId)) return false;

  const query = normalizeText(viewFilters.value?.query || '').trim();
  return (
    matchesQueryFilter(item, query) &&
    matchesLabelFilter(item) &&
    matchesAssigneeFilter(item) &&
    matchesStatusFilter(item)
  );
};

const getFilteredItemsForStage = stageId => {
  const stageItems = getItemsForStage(stageId);
  return stageItems.filter(item => isItemVisible(item, stageId));
};

const handleMoveItem = async ({ item, stageId }) => {
  const itemId = Number(item?.id);
  const currentStageId = Number(item.funnelStageId || item.funnel_stage_id);
  const newStageId = Number(stageId);
  if (!itemId || !stageId || newStageId === currentStageId) return;

  const lockKey = `${props.funnelId}:${itemId}`;
  if (movingItems.value.has(lockKey)) return;
  movingItems.value.add(lockKey);

  try {
    await store.dispatch('kanban/updateItem', {
      funnelId: props.funnelId,
      itemId,
      data: { funnel_stage_id: newStageId },
    });

    emit('itemMoved', { item, newStageId });
  } catch (error) {
    const fallbackMessage = t('KANBAN.ITEMS.MOVE_ERROR');
    const validationErrors = error?.response?.data?.errors;
    let normalizedValidationErrors = null;
    if (Array.isArray(validationErrors)) {
      normalizedValidationErrors = validationErrors.join(', ');
    } else if (
      validationErrors &&
      typeof validationErrors === 'object' &&
      Object.keys(validationErrors).length
    ) {
      normalizedValidationErrors = Object.values(validationErrors)
        .flat()
        .join(', ');
    }
    const backendMessage =
      error?.response?.data?.message ||
      error?.response?.data?.error ||
      normalizedValidationErrors ||
      fallbackMessage;

    useAlert(backendMessage);

    await Promise.allSettled(
      [currentStageId, newStageId]
        .filter(id => !Number.isNaN(id) && id > 0)
        .map(id =>
          store.dispatch('kanban/fetchFunnelItemsPage', {
            funnelId: props.funnelId,
            stageId: id,
            append: false,
          })
        )
    );
  } finally {
    movingItems.value.delete(lockKey);
  }
};

const handleScheduleMessage = conversation => {
  emit('scheduleMessage', conversation);
};

const confirmDialogRef = ref(null);
const confirmState = ref({
  title: '',
  message: '',
  confirmLabel: '',
  action: null,
});

const openConfirm = ({ title, message, confirmLabel, action }) => {
  confirmState.value = { title, message, confirmLabel, action };
  nextTick(() => confirmDialogRef.value?.open?.());
};

const runConfirm = async () => {
  const { action } = confirmState.value;
  confirmDialogRef.value?.close?.();
  if (typeof action === 'function') await action();
};

const performRemoveItem = async item => {
  try {
    await store.dispatch('kanban/deleteItem', {
      funnelId: props.funnelId,
      itemId: item.id,
    });
    emit('removeItem', item);
  } catch (_) {
    useAlert(t('KANBAN.ITEMS.MOVE_ERROR'));
  }
};

const handleRemoveItem = item => {
  openConfirm({
    title: t('KANBAN.ITEMS.REMOVE'),
    message: t('KANBAN.ITEMS.CONFIRM_REMOVE'),
    confirmLabel: t('KANBAN.ITEMS.REMOVE'),
    action: () => performRemoveItem(item),
  });
};

const handleEditStage = stage => {
  if (!stage) return;
  selectedStage.value = { ...stage };
  showStageForm.value = true;
};

const handleCreateStage = () => {
  // Blank object (no id) puts StageForm into create mode.
  selectedStage.value = { name: '', color: '#94a3b8', automation_type: null };
  showStageForm.value = true;
};

const showAddModal = ref(false);
const addStage = ref(null);

const handleAddCard = stage => {
  addStage.value = stage;
  showAddModal.value = true;
};

const handleConversationAdded = async () => {
  showAddModal.value = false;
  const stageId = addStage.value?.id;
  if (stageId) {
    await store.dispatch('kanban/fetchFunnelItemsPage', {
      funnelId: props.funnelId,
      stageId: Number(stageId),
      limit: 30,
      append: false,
    });
  }
  addStage.value = null;
};

const handleStageSaved = async () => {
  await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  await store.dispatch('kanban/bootstrapView', {
    view: 'kanban',
    funnelId: props.funnelId,
    force: true,
  });

  showStageForm.value = false;
  selectedStage.value = null;
};

let isReordering = false;

const handleStageReorder = async evt => {
  if (isReordering) return;

  const hasMoved =
    evt.moved ||
    (evt.oldIndex !== undefined &&
      evt.newIndex !== undefined &&
      evt.oldIndex !== evt.newIndex);

  if (!hasMoved || localStages.value.length === 0) return;

  isReordering = true;
  try {
    const stageIds = localStages.value
      .map(stage => Number(stage.id))
      .filter(stageId => !Number.isNaN(stageId));

    if (!stageIds.length) return;

    await store.dispatch('kanban/reorderStages', {
      funnelId: props.funnelId,
      stageIds,
    });

    await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  } catch (error) {
    useAlert(error?.response?.data?.error || t('KANBAN.STAGES.SAVE_ERROR'));
    await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  } finally {
    isReordering = false;
  }
};

const performDeleteStage = async stage => {
  try {
    await store.dispatch('kanban/deleteStage', {
      funnelId: props.funnelId,
      stageId: stage.id,
    });
    await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  } catch (_) {
    useAlert(t('KANBAN.STAGES.DELETE_ERROR'));
  }
};

const handleDeleteStage = stage => {
  if (!stage) return;
  openConfirm({
    title: t('KANBAN.STAGES.DELETE'),
    message: t('KANBAN.STAGES.CONFIRM_DELETE'),
    confirmLabel: t('KANBAN.STAGES.DELETE'),
    action: () => performDeleteStage(stage),
  });
};
</script>

<template>
  <div
    class="kanban-board-container flex h-full w-full min-h-0 flex-col overflow-hidden"
  >
    <div
      v-if="isLoading && stages.length === 0"
      class="flex h-full items-center justify-center"
    >
      <div
        class="flex max-w-sm flex-col items-center justify-center text-center"
      >
        <Icon
          icon="i-lucide-loader-2"
          class="mb-4 size-8 animate-spin text-n-slate-10"
        />
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('KANBAN.LOADING') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('KANBAN.LOADING_CONVERSATIONS') }}
        </p>
      </div>
    </div>

    <div
      v-else
      class="kanban-board flex h-full gap-4 overflow-x-auto overflow-y-hidden bg-n-background px-5 py-4"
    >
      <draggable
        v-model="localStages"
        :group="{ name: 'kanban-stages', pull: false, put: false }"
        item-key="id"
        handle=".kanban-column-drag-handle"
        class="flex h-full gap-4"
        :animation="200"
        ghost-class="kanban-stage-ghost"
        drag-class="kanban-stage-drag"
        @end="handleStageReorder"
      >
        <template #item="{ element: stage }">
          <KanbanColumn
            :key="`stage-${stage.id}`"
            :funnel-id="funnelId"
            :stage="stage"
            :items="getFilteredItemsForStage(stage.id)"
            :conversations="conversations"
            @move-item="handleMoveItem"
            @schedule-message="handleScheduleMessage"
            @remove-item="handleRemoveItem"
            @edit-stage="handleEditStage"
            @delete-stage="handleDeleteStage"
            @add-card="handleAddCard"
          />
        </template>
      </draggable>

      <button
        v-if="stages.length > 0"
        class="kanban-add-stage group flex h-full shrink-0 flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-n-weak bg-n-slate-2/30 px-4 text-n-slate-10 transition hover:border-n-slate-6 hover:bg-n-slate-2/60 hover:text-n-slate-12 dark:bg-n-solid-2/40"
        @click="handleCreateStage"
      >
        <Icon icon="i-lucide-plus" class="size-5" />
        <span class="text-sm font-medium">{{ t('KANBAN.STAGES.CREATE') }}</span>
      </button>

      <div
        v-if="stages.length === 0"
        class="flex w-full flex-col items-center justify-center rounded-xl border-2 border-dashed border-n-weak bg-n-slate-2/50 dark:bg-n-solid-2 p-8 text-center"
      >
        <Icon icon="i-lucide-columns-3" class="mb-3 size-9 text-n-slate-10" />
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ t('KANBAN.STAGES.NO_STAGES') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('KANBAN.STAGES.NO_STAGES_DESCRIPTION') }}
        </p>
        <p class="mt-1 text-xs text-n-slate-9">
          {{ t('KANBAN.STAGES.EDIT_FUNNEL_HINT') }}
        </p>
      </div>
    </div>

    <StageForm
      :show="showStageForm && !!selectedStage"
      :stage="selectedStage"
      :funnel-id="funnelId"
      @close="
        () => {
          showStageForm = false;
          selectedStage = null;
        }
      "
      @saved="handleStageSaved"
    />

    <AddConversationModal
      :show="showAddModal"
      :stage="addStage"
      :funnel-id="funnelId"
      @close="
        () => {
          showAddModal = false;
          addStage = null;
        }
      "
      @added="handleConversationAdded"
    />

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      :title="confirmState.title"
      :description="confirmState.message"
      :confirm-button-label="confirmState.confirmLabel"
      @confirm="runConfirm"
    />
  </div>
</template>

<style scoped>
.kanban-board {
  min-width: 100%;
  scrollbar-width: thin;
  scrollbar-color: rgb(var(--border-weak)) transparent;
  background-image: radial-gradient(
      120% 80% at 50% -10%,
      rgba(99, 102, 241, 0.05),
      transparent 60%
    ),
    radial-gradient(rgba(148, 163, 184, 0.07) 1px, transparent 1px);
  background-size:
    100% 100%,
    24px 24px;
}

.kanban-add-stage {
  width: var(--kanban-col-width, 304px);
}

.kanban-board::-webkit-scrollbar {
  height: 8px;
}

.kanban-board::-webkit-scrollbar-track {
  background: transparent;
}

.kanban-board::-webkit-scrollbar-thumb {
  background-color: rgb(var(--border-weak));
  border-radius: 4px;
}

.kanban-board::-webkit-scrollbar-thumb:hover {
  background-color: rgb(var(--border-strong));
}
</style>
