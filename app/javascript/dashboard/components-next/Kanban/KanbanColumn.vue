<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';
import Icon from 'next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  items: {
    type: Array,
    default: () => [],
  },
  conversations: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['move-item', 'schedule-message', 'remove-item', 'edit-stage', 'delete-stage']);

const { t } = useI18n();
const showStageMenu = ref(false);

const handleEditStage = () => {
  showStageMenu.value = false;
  emit('edit-stage', props.stage);
};

const handleDeleteStage = () => {
  showStageMenu.value = false;
  emit('delete-stage', props.stage);
};

const handleAdd = (evt) => {
  console.log('handleAdd chamado:', evt);
  if (evt.added) {
    console.log('Item adicionado:', evt.added.element, 'Stage ID:', props.stage.id);
    emit('move-item', {
      item: evt.added.element,
      newIndex: evt.added.newIndex,
      oldIndex: evt.added.oldIndex,
      stageId: props.stage.id,
    });
  }
};

const handleChange = (evt) => {
  console.log('handleChange chamado:', evt);
  // O evento change é disparado quando há mudanças, incluindo quando um item é adicionado
  if (evt.added) {
    console.log('Change: Item adicionado:', evt.added.element, 'Stage ID:', props.stage.id);
    emit('move-item', {
      item: evt.added.element,
      newIndex: evt.added.newIndex,
      oldIndex: evt.added.oldIndex,
      stageId: props.stage.id,
    });
  }
};

const handleMove = (evt) => {
  console.log('handleMove chamado:', evt);
  // Quando um item é movido dentro da mesma coluna, não precisa fazer nada
  // O @add já captura quando é movido entre colunas
  if (evt.moved) {
    console.log('Item movido dentro da mesma coluna:', evt.moved);
    // Se o item foi movido dentro da mesma coluna, não emitir evento
    // O drag and drop do vuedraggable já atualiza a ordem localmente
  }
  showStageMenu.value = false;
};

const itemsWithConversations = computed(() => {
  return props.items.map(item => {
    const conversationKey =
      item.conversation?.displayId ||
      item.conversation?.display_id ||
      item.conversation?.id ||
      item.conversationId ||
      item.conversation_id;
    return {
      ...item,
      conversation:
        props.conversations[conversationKey] ||
        item.conversation || {
          id: conversationKey,
          displayId: conversationKey,
          status: 'open',
        },
    };
  });
});

</script>

<template>
  <div class="kanban-column flex-shrink-0 w-80 bg-n-solid-2 rounded-xl p-4 border border-n-weak shadow-sm flex flex-col h-full">
    <!-- Column Header -->
    <div class="flex items-center justify-between mb-4 pb-3 border-b border-n-weak group">
      <div class="flex items-center gap-2 flex-1 min-w-0">
        <div
          v-if="stage.color"
          :class="['w-3 h-3 rounded-full flex-shrink-0']"
          :style="{ backgroundColor: stage.color }"
        />
        <h3 class="font-semibold text-sm text-n-slate-12 truncate">
          {{ stage.name }}
        </h3>
        <span class="text-xs text-n-slate-10 bg-n-solid-3 px-2 py-0.5 rounded-full font-medium flex-shrink-0">
          {{ items.length }}
        </span>
      </div>
      <div class="relative">
        <Button
          size="xs"
          variant="ghost"
          icon="i-lucide-more-vertical"
          class="opacity-0 group-hover:opacity-100 transition-opacity !h-6 !w-6 !p-0"
          @click.stop="showStageMenu = !showStageMenu"
        />
        <div
          v-if="showStageMenu"
          class="absolute right-0 top-8 w-48 bg-n-solid-2 rounded-lg shadow-lg border border-n-weak py-1 z-20"
          @click.stop
        >
          <button
            class="w-full text-left px-4 py-2 text-sm text-n-slate-11 hover:bg-n-solid-3 flex items-center gap-2 transition-colors"
            @click="handleEditStage"
          >
            <Icon icon="i-lucide-edit" class="size-4" />
            {{ t('KANBAN.STAGES.EDIT') }}
          </button>
          <button
            class="w-full text-left px-4 py-2 text-sm text-ruby-11 hover:bg-n-ruby-3 flex items-center gap-2 transition-colors"
            @click="handleDeleteStage"
          >
            <Icon icon="i-lucide-trash" class="size-4" />
            {{ t('KANBAN.STAGES.DELETE') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Column Content -->
    <draggable
      :model-value="itemsWithConversations"
      :group="{ name: 'kanban-items', pull: true, put: true }"
      item-key="id"
      class="kanban-column-content flex flex-col flex-1 gap-3 overflow-y-auto overflow-x-hidden"
      :animation="200"
      ghost-class="kanban-ghost"
      drag-class="kanban-drag"
      @end="handleMove"
      @add="handleAdd"
      @change="handleChange"
    >
      <template #item="{ element: item }">
        <KanbanCard
          :item="item"
          :conversation="item.conversation || {}"
          @move="emit('move-item', { item })"
          @schedule-message="emit('schedule-message', $event)"
          @remove="emit('remove-item', item)"
        />
      </template>
      <template #footer>
        <div
          v-if="items.length === 0"
          class="flex flex-col items-center justify-center py-10 text-center rounded-lg border border-dashed border-n-weak bg-n-solid-3"
        >
          <Icon icon="i-lucide-inbox" class="size-12 text-n-slate-8 mb-3 opacity-50" />
          <p class="text-sm text-n-slate-10">{{ t('KANBAN.ITEMS.NO_ITEMS') }}</p>
        </div>
      </template>
    </draggable>
  </div>
</template>

<style scoped>
.kanban-column-content {
  flex: 1 1 auto;
  min-height: 200px;
  overflow-y: auto;
  overflow-x: hidden;
  display: flex;
  flex-direction: column;
}

.kanban-column-content::-webkit-scrollbar {
  width: 6px;
}

.kanban-column-content::-webkit-scrollbar-track {
  background: transparent;
}

.kanban-column-content::-webkit-scrollbar-thumb {
  background-color: var(--n-weak);
  border-radius: 3px;
}

.kanban-column-content::-webkit-scrollbar-thumb:hover {
  background-color: var(--n-strong);
}

:deep(.kanban-ghost) {
  opacity: 0.4;
  background: var(--n-blue-3);
  border: 2px dashed var(--n-blue-9);
}

:deep(.kanban-drag) {
  opacity: 0.8;
  transform: rotate(2deg);
}
</style>
