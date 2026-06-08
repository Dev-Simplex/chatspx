<script setup>
// KanbanBoard redesenhado (P1-08).
// - Vuex segue como fonte (consumers do KanbanColumn ainda dependem)
// - Novo: integração com useKanbanBoardStore (Pinia) para real-time
// - Novo: subscribe ao KanbanChannel (P1-13) via useKanbanCable
// - Novo: PDND monitor (P1-07) para drag entre colunas
// - Empty state via KanbanEmptyState quando funil sem stages/cards
import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import KanbanColumn from './KanbanColumn.vue';
import KanbanEmptyState from './KanbanEmptyState.vue';
import StageForm from './StageForm.vue';
import KanbanTemplateConfirmModal from './KanbanTemplateConfirmModal.vue';
import KanbanBoardSkeleton from './KanbanBoardSkeleton.vue';
import KanbanFirstTimeTooltip from './KanbanFirstTimeTooltip.vue';
import KanbanWipOverrideDialog from './KanbanWipOverrideDialog.vue';
import KanbanConfirmDialog from './KanbanConfirmDialog.vue';
import { useAlert } from 'dashboard/composables';
import { useKanbanBoardStore } from 'dashboard/store/pinia/kanban/board';
import { useKanbanCable } from 'dashboard/composables/kanban/useKanbanCable';
import { useKanbanBoardMonitor } from 'dashboard/composables/kanban/useKanbanDrag';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  funnelId: { type: Number, required: true },
  // P2-07: modo seleção múltipla (passa down para cards).
  bulkMode: { type: Boolean, default: false },
});
const emit = defineEmits([
  'itemMoved',
  'scheduleMessage',
  'removeItem',
  'openDrawer',
  'wonLost',
]);

const store = useStore();
const { t } = useI18n();
// Pinia store é usada por composables (real-time / drag); referência mantida
// para garantir mount/HMR.
useKanbanBoardStore();
const { subscribe, unsubscribe } = useKanbanCable();
const snackbar = useKanbanSnackbar();

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

const showStageForm = ref(false);
const selectedStage = ref(null);
const movingItems = ref(new Set());

// P3-03 + P3-08: derive pending UI from Pinia store
const piniaBoard = useKanbanBoardStore();
const pendingTemplate = computed(() => piniaBoard.pendingTemplateConfirm);
const pendingWip = computed(() => piniaBoard.pendingWipOverride);

const pendingTemplateStage = computed(() => {
  const id = pendingTemplate.value?.stageId;
  return id ? piniaBoard.stageById(id) : null;
});

const pendingTemplatePreview = computed(() => {
  const stage = pendingTemplateStage.value;
  if (!stage) return '';
  return (
    stage.settings?.template_preview ||
    stage.settings?.templatePreview ||
    stage.settings?.template_body ||
    ''
  );
});

const pendingTemplateVariables = computed(() => {
  const stage = pendingTemplateStage.value;
  if (!stage) return {};
  const itemId = pendingTemplate.value?.itemId;
  const item = itemId ? piniaBoard.itemById(itemId) : null;
  const conv = item?.conversation || {};
  const contact = conv?.contact || conv?.meta?.sender || {};
  const fullName = contact.name || '';
  return {
    name: fullName.split(' ')[0] || '',
    last_name: fullName.split(' ').slice(-1)[0] || '',
    full_name: fullName,
    phone: contact.phone_number || '',
    stage: stage.name || '',
  };
});

const closeTemplateModal = () => piniaBoard.clearPendingTemplateConfirm();
const acceptWipOverride = async () => {
  const p = pendingWip.value;
  if (!p) return;
  piniaBoard.clearPendingWipOverride();
  await piniaBoard.moveItem({
    itemId: p.itemId,
    toStageId: p.toStageId,
    toPosition: p.toPosition,
    bypassWip: true,
  });
};
const cancelWipOverride = () => piniaBoard.clearPendingWipOverride();

const normalizeText = v => String(v || '').toLowerCase();

const extractAssigneeId = src => {
  if (!src) return null;
  return (
    src.assigneeId ||
    src.assignee_id ||
    src.assignee?.id ||
    src.assignee?.user?.id ||
    src.meta?.assignee?.id ||
    src.meta?.assignee_id ||
    null
  );
};

const resolveConversationKey = item => {
  const v =
    item?.conversationId ||
    item?.conversation_id ||
    item?.conversation?.id ||
    item?.conversation?.displayId ||
    item?.conversation?.display_id;
  return v == null ? null : String(v);
};

const resolveConversationId = item => {
  const v =
    item?.conversationId || item?.conversation_id || item?.conversation?.id;
  const n = Number(v);
  return !Number.isNaN(n) && n > 0 ? n : null;
};

const getItemsForStage = stageId =>
  store.getters['kanban/getFunnelItems'](props.funnelId, stageId);

const conversations = computed(() => {
  const map = {};
  (stages.value || []).forEach(stage => {
    getItemsForStage(stage.id).forEach(item => {
      const key = resolveConversationKey(item);
      if (!key || map[key]) return;
      const itemConv = item.conversation || {};
      const convId = resolveConversationId(item);
      const storeConv =
        convId && typeof getConversationById.value === 'function'
          ? getConversationById.value(convId)
          : null;
      const merged = { ...(storeConv || {}), ...itemConv };
      const contact =
        merged.contact || storeConv?.meta?.sender || storeConv?.contact || {};
      map[key] = {
        ...merged,
        id: convId || merged.id || null,
        displayId: merged.displayId || merged.display_id || convId || key,
        status: merged.status || 'open',
        assigneeId: extractAssigneeId(merged),
        contact: { ...contact },
      };
    });
  });
  return map;
});

const getItemConversation = item => {
  const key = resolveConversationKey(item);
  if (key && conversations.value[key]) return conversations.value[key];
  return item?.conversation || {};
};

const getItemLabels = item => {
  const convId = resolveConversationId(item);
  if (!convId || typeof getConversationLabels.value !== 'function') return [];
  const labels = getConversationLabels.value(convId);
  return Array.isArray(labels) ? labels : [];
};

const matchesQueryFilter = (item, q) => {
  if (!q) return true;
  const c = getItemConversation(item);
  const hay = [
    c?.contact?.name,
    c?.contact?.phone_number,
    c?.contact?.phoneNumber,
    c?.displayId,
    c?.lastMessage?.content,
    c?.last_message?.content,
  ]
    .map(normalizeText)
    .join(' ');
  return hay.includes(q);
};

const matchesLabelFilter = item => {
  const ids = viewFilters.value?.labelIds || [];
  if (!ids.length) return true;
  const set = new Set(ids.map(Number));
  return getItemLabels(item).some(l => set.has(Number(l.id)));
};

const matchesAssigneeFilter = item => {
  const selected = Number(viewFilters.value?.assigneeId || 0);
  if (!selected) return true;
  const a =
    extractAssigneeId(item?.conversation) ||
    extractAssigneeId(getItemConversation(item));
  return Number(a) === selected;
};

const matchesStatusFilter = item => {
  const s = viewFilters.value?.status || 'all';
  if (s === 'all') return true;
  return (getItemConversation(item)?.status || 'open') === s;
};

const matchesStageFilter = stageId => {
  const ids = viewFilters.value?.stageIds || [];
  if (!ids.length) return true;
  return ids.map(Number).includes(Number(stageId));
};

const getFilteredItemsForStage = stageId => {
  if (!matchesStageFilter(stageId)) return [];
  const q = normalizeText(viewFilters.value?.query || '').trim();
  return getItemsForStage(stageId).filter(
    item =>
      matchesQueryFilter(item, q) &&
      matchesLabelFilter(item) &&
      matchesAssigneeFilter(item) &&
      matchesStatusFilter(item)
  );
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

    // KANBAN-P2-06: detectar won/loss stage → abrir modal.
    const destStage = (stages.value || []).find(
      s => Number(s.id) === Number(newStageId)
    );
    const wonLossType =
      destStage?.won_loss_type || destStage?.wonLossType || null;
    if (wonLossType) {
      emit('wonLost', { item, stage: destStage, mode: wonLossType });
    }
  } catch (error) {
    const fallback = t('KANBAN.ITEMS.MOVE_ERROR');
    const errs = error?.response?.data?.errors;
    let errMsg = null;
    if (Array.isArray(errs)) {
      errMsg = errs.join(', ');
    } else if (errs && typeof errs === 'object' && Object.keys(errs).length) {
      errMsg = Object.values(errs).flat().join(', ');
    }
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        errMsg ||
        fallback
    );
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

const handleScheduleMessage = c => emit('scheduleMessage', c);

const handleRemoveItem = async item => {
  // Soft-delete (otimista): chama Vuex e abre snackbar com Desfazer.
  // Em P2-04 será trocado pelo restore endpoint dedicado.
  const snapshotStageId = Number(item.funnelStageId || item.funnel_stage_id);
  try {
    await store.dispatch('kanban/deleteItem', {
      funnelId: props.funnelId,
      itemId: item.id,
    });
    emit('removeItem', item);
    snackbar.show({
      message: t('KANBAN.SNACKBAR.CARD_DELETED'),
      timeout: 7000,
      action: {
        label: t('KANBAN.SNACKBAR.UNDO'),
        onClick: async () => {
          try {
            await store.dispatch('kanban/createItem', {
              funnelId: props.funnelId,
              data: {
                conversation_id: item.conversationId || item.conversation_id,
                funnel_stage_id: snapshotStageId,
              },
            });
            await store.dispatch('kanban/bootstrapView', {
              view: 'kanban',
              funnelId: props.funnelId,
              force: true,
            });
          } catch (_) {
            useAlert(t('KANBAN.SNACKBAR.UNDO_FAILED'));
          }
        },
      },
    });
  } catch (_) {
    useAlert(t('KANBAN.ITEMS.MOVE_ERROR'));
  }
};

const handleEditStage = stage => {
  if (!stage) return;
  selectedStage.value = { ...stage };
  showStageForm.value = true;
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

const deleteStageDialog = ref({ open: false, stage: null });

const handleDeleteStage = stage => {
  if (!stage) return;
  deleteStageDialog.value = { open: true, stage };
};

const cancelDeleteStage = () => {
  deleteStageDialog.value = { open: false, stage: null };
};

const confirmDeleteStage = async () => {
  const stage = deleteStageDialog.value.stage;
  deleteStageDialog.value = { open: false, stage: null };
  if (!stage) return;
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

const totalItemsAcrossStages = computed(() =>
  (stages.value || []).reduce(
    (sum, s) => sum + (getItemsForStage(s.id)?.length || 0),
    0
  )
);

// PDND monitor: ao soltar um card em outra coluna, encontra o item e
// despacha handleMoveItem (que persiste via Vuex e refaz fetch em erro).
useKanbanBoardMonitor({
  moveItem: async ({ itemId, toStageId }) => {
    const item = (stages.value || [])
      .flatMap(s => getItemsForStage(s.id))
      .find(i => Number(i.id) === Number(itemId));
    if (!item) return;
    await handleMoveItem({ item, stageId: toStageId });
  },
});

onMounted(() => subscribe(props.funnelId));
onUnmounted(() => unsubscribe());
watch(
  () => props.funnelId,
  next => subscribe(next)
);
</script>

<template>
  <div
    class="flex h-full w-full min-h-0 flex-col overflow-hidden bg-slate-50 dark:bg-n-solid-1"
  >
    <KanbanBoardSkeleton v-if="isLoading && stages.length === 0" />

    <div
      v-else-if="stages.length === 0"
      class="flex-1 flex items-center justify-center"
    >
      <KanbanEmptyState variant="funnel" />
    </div>

    <div
      v-else-if="totalItemsAcrossStages === 0"
      class="flex-1 flex items-center justify-center"
    >
      <KanbanEmptyState variant="funnel" />
    </div>

    <div
      v-else
      class="flex flex-1 min-h-0 gap-3 overflow-x-auto overflow-y-hidden px-4 py-4"
    >
      <KanbanColumn
        v-for="stage in stages"
        :key="`stage-${stage.id}`"
        :funnel-id="funnelId"
        :stage="stage"
        :items="getFilteredItemsForStage(stage.id)"
        :conversations="conversations"
        :bulk-mode="bulkMode"
        @move-item="handleMoveItem"
        @schedule-message="handleScheduleMessage"
        @remove-item="handleRemoveItem"
        @edit-stage="handleEditStage"
        @delete-stage="handleDeleteStage"
        @open-drawer="item => emit('openDrawer', item)"
      />
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

    <!-- P3-03 -->
    <KanbanTemplateConfirmModal
      :open="!!pendingTemplate"
      :funnel-id="funnelId"
      :item-id="pendingTemplate?.itemId"
      :stage="pendingTemplateStage || {}"
      :template-preview="pendingTemplatePreview"
      :template-name="pendingTemplate?.templateId"
      :variables="pendingTemplateVariables"
      @close="closeTemplateModal"
      @sent="closeTemplateModal"
    />

    <!-- P3-08 -->
    <KanbanWipOverrideDialog
      :open="!!pendingWip"
      :over="pendingWip ? pendingWip.count - pendingWip.limit + 1 : 0"
      :limit="pendingWip?.limit || 0"
      @cancel="cancelWipOverride"
      @confirm="acceptWipOverride"
    />

    <!-- P3-07 -->
    <KanbanFirstTimeTooltip v-if="stages.length > 0" />

    <!-- DoD §35.3 -->
    <KanbanConfirmDialog
      :open="deleteStageDialog.open"
      :title="
        deleteStageDialog.stage?.name
          ? t('KANBAN.CONFIRM.DELETE_STAGE_TITLE', {
              name: deleteStageDialog.stage.name,
            })
          : t('KANBAN.CONFIRM.DELETE_STAGE_GENERIC_TITLE')
      "
      :message="t('KANBAN.CONFIRM.DELETE_STAGE_GENERIC_BODY')"
      :confirm-label="t('KANBAN.CONFIRM.DELETE_CONFIRM_LABEL')"
      variant="destructive"
      @confirm="confirmDeleteStage"
      @cancel="cancelDeleteStage"
    />
  </div>
</template>
