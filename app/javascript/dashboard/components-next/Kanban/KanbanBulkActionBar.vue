<script setup>
// KANBAN-P2-07: barra de ações fixa quando ≥1 card selecionado.
// Aparece embaixo no centro. Botões: Mover para... | Excluir | Cancelar.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanConfirmDialog from './KanbanConfirmDialog.vue';
import KanbanAPI from 'dashboard/api/kanban';
import { useKanbanBoardStore } from 'dashboard/store/pinia/kanban/board';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  funnelId: { type: [Number, String, null], default: null },
  stages: { type: Array, default: () => [] },
});

const emit = defineEmits(['refreshed']);

const { t } = useI18n();
const boardStore = useKanbanBoardStore();
const snackbar = useKanbanSnackbar();
const { selectedItemIds } = storeToRefs(boardStore);

const showMoveMenu = ref(false);
const busy = ref(false);

const count = computed(() => selectedItemIds.value.length);

const cancel = () => {
  boardStore.clearSelection();
  showMoveMenu.value = false;
};

const moveTo = async stageId => {
  if (!props.funnelId || !stageId || !count.value) return;
  busy.value = true;
  try {
    await KanbanAPI.bulkMoveItems(props.funnelId, [], stageId, [
      ...selectedItemIds.value,
    ]);
    const stageName =
      (props.stages.find(s => Number(s.id) === Number(stageId)) || {}).name ||
      '';
    snackbar.show({
      message: t('KANBAN.BULK.MOVED', { count: count.value }),
      timeout: 6000,
    });
    emit('refreshed', { stageId, stageName });
    boardStore.clearSelection();
    showMoveMenu.value = false;
  } catch (e) {
    useAlert(e?.message || t('KANBAN.BULK.ERROR'));
  } finally {
    busy.value = false;
  }
};

const confirmDialog = ref({ open: false });

const onDelete = () => {
  if (!count.value || !props.funnelId) return;
  confirmDialog.value = { open: true };
};

const cancelDelete = () => {
  confirmDialog.value = { open: false };
};

const confirmDelete = async () => {
  confirmDialog.value = { open: false };
  if (!count.value || !props.funnelId) return;
  busy.value = true;
  try {
    await KanbanAPI.bulkDeleteItems(props.funnelId, [...selectedItemIds.value]);
    snackbar.show({
      message: t('KANBAN.BULK.DELETED', { count: count.value }),
      timeout: 6000,
    });
    emit('refreshed', {});
    boardStore.clearSelection();
  } catch (e) {
    useAlert(e?.message || t('KANBAN.BULK.ERROR'));
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div
    v-if="count > 0"
    class="fixed left-1/2 -translate-x-1/2 bottom-6 z-40 px-4 py-2 rounded-2xl shadow-xl bg-slate-900 text-white flex items-center gap-2"
    role="region"
    :aria-label="t('KANBAN.BULK.ARIA_REGION')"
  >
    <span class="text-sm font-medium">
      {{ t('KANBAN.BULK.SELECTED', { count }) }}
    </span>

    <div class="relative">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 px-3 h-8 rounded-lg bg-iris-600 hover:bg-iris-700 text-sm font-medium"
        :disabled="busy"
        @click="showMoveMenu = !showMoveMenu"
      >
        <Icon icon="i-lucide-move" class="size-4" />
        {{ t('KANBAN.BULK.MOVE_TO') }}
      </button>
      <ul
        v-if="showMoveMenu"
        class="absolute bottom-10 left-0 w-56 rounded-xl bg-slate-800 border border-slate-700 py-1 max-h-72 overflow-y-auto"
      >
        <li
          v-for="stage in stages"
          :key="stage.id"
          class="px-3 py-2 text-sm hover:bg-slate-700 cursor-pointer flex items-center gap-2"
          @click="moveTo(stage.id)"
        >
          <span
            class="size-2.5 rounded-full"
            :style="{ background: stage.color || '#94a3b8' }"
          />
          {{ stage.name }}
        </li>
      </ul>
    </div>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-8 rounded-lg bg-ruby-600 hover:bg-ruby-700 text-sm font-medium"
      :disabled="busy"
      @click="onDelete"
    >
      <Icon icon="i-lucide-trash-2" class="size-4" />
      {{ t('KANBAN.BULK.DELETE') }}
    </button>

    <button
      type="button"
      class="inline-flex items-center gap-1.5 px-3 h-8 rounded-lg bg-slate-700 hover:bg-slate-600 text-sm"
      @click="cancel"
    >
      <Icon icon="i-lucide-x" class="size-4" />
      {{ t('KANBAN.BULK.CANCEL') }}
    </button>

    <KanbanConfirmDialog
      :open="confirmDialog.open"
      :title="t('KANBAN.CONFIRM.BULK_DELETE_TITLE', { count })"
      :message="t('KANBAN.CONFIRM.BULK_DELETE_BODY')"
      :confirm-label="t('KANBAN.CONFIRM.DELETE_CONFIRM_LABEL')"
      variant="destructive"
      @confirm="confirmDelete"
      @cancel="cancelDelete"
    />
  </div>
</template>
