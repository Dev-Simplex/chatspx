<script setup>
import { computed, onMounted, watch, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import KanbanColumn from './KanbanColumn.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['item-moved', 'schedule-message', 'remove-item', 'edit-stage', 'delete-stage']);

const store = useStore();
const { t } = useI18n();

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);

const conversations = computed(() => {
  const allStages = stages.value;
  const conversationMap = {};
  
  if (!Array.isArray(allStages)) {
    return conversationMap;
  }
  
  allStages.forEach(stage => {
    if (!stage || !stage.id) return;
    const items = getItemsForStage(stage.id);
    if (!Array.isArray(items)) return;
    
    items.forEach(item => {
      const conversationKey =
        item.conversationId ||
        item.conversation_id ||
        item.conversation?.id ||
        item.conversation?.displayId ||
        item.conversation?.display_id;
      if (!conversationKey || conversationMap[conversationKey]) return;

      const getConversationById = store.getters['conversations/getConversationById'];
      const storeConversation = getConversationById
        ? getConversationById(Number(conversationKey))
        : null;
      const itemConversation = item.conversation || {};

      if (storeConversation && storeConversation.id) {
        conversationMap[conversationKey] = {
          ...storeConversation,
          ...itemConversation,
        };
      } else if (Object.keys(itemConversation).length > 0) {
        conversationMap[conversationKey] = itemConversation;
      } else {
        conversationMap[conversationKey] = {
          id: conversationKey,
          displayId: conversationKey,
          status: 'open',
          contactId: item.conversation?.contactId || item.conversation?.contact_id,
        };
      }
    });
  });
  
  return conversationMap;
});

const isLoading = computed(() => store.getters['kanban/getUIFlags'].isFetching);

// Estado de loading robusto que aguarda todos os dados
const isLoadingData = ref(true);

const getItemsForStage = (stageId) => {
  return store.getters['kanban/getFunnelItems'](props.funnelId, stageId);
};

const handleMoveItem = async ({ item, newIndex, oldIndex, stageId }) => {
  console.log('handleMoveItem chamado:', { item, newIndex, oldIndex, stageId });
  
  // Normalizar IDs para comparação (pode ser string ou número)
  const currentStageId = Number(item.funnelStageId || item.funnel_stage_id);
  const newStageId = Number(stageId);
  
  console.log('Comparação de IDs:', { currentStageId, newStageId, sãoDiferentes: newStageId !== currentStageId });
  
  if (stageId && newStageId !== currentStageId) {
    console.log('Iniciando movimentação do item...');
    try {
      await store.dispatch('kanban/updateItem', {
        funnelId: props.funnelId,
        itemId: item.id,
        data: {
          funnel_stage_id: newStageId,
        },
      });
      
      console.log('Item atualizado, recarregando dados...');
      
      // Recarregar os itens do funil para refletir a mudança
      await store.dispatch('kanban/fetchFunnelItems', {
        funnelId: props.funnelId,
      });
      
      emit('item-moved', { item, newStageId: newStageId });
      console.log('Item movido com sucesso!');
    } catch (error) {
      console.error('Erro ao mover item:', error);
    }
  } else {
    console.log('Movimentação ignorada - mesma etapa ou stageId inválido');
  }
};

const handleScheduleMessage = (conversation) => {
  emit('schedule-message', conversation);
};

const handleRemoveItem = async (item) => {
  if (confirm(t('KANBAN.ITEMS.CONFIRM_REMOVE'))) {
    try {
      await store.dispatch('kanban/deleteItem', {
        funnelId: props.funnelId,
        itemId: item.id,
      });
      emit('remove-item', item);
    } catch (error) {
      console.error('Erro ao remover item:', error);
    }
  }
};

const handleEditStage = (stage) => {
  // Emitir para o parent ou abrir modal de edição
  console.log('Editar etapa:', stage);
  // TODO: Implementar modal de edição de etapa
};

const handleDeleteStage = async (stage) => {
  if (!confirm(t('KANBAN.STAGES.CONFIRM_DELETE'))) {
    return;
  }
  
  try {
    await store.dispatch('kanban/deleteStage', {
      funnelId: props.funnelId,
      stageId: stage.id,
    });
    // Recarregar etapas após deletar
    await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  } catch (error) {
    console.error('Erro ao deletar etapa:', error);
    alert(t('KANBAN.STAGES.DELETE_ERROR'));
  }
};

const loadData = async () => {
  if (!props.funnelId) {
    isLoadingData.value = false;
    return;
  }
  
  isLoadingData.value = true;
  
    try {
    // 1. Carregar itens do funil
      await store.dispatch('kanban/fetchFunnelItems', {
        funnelId: props.funnelId,
      });
    
    // 2. Aguardar um pouco para garantir que os dados estão no store
    await new Promise(resolve => setTimeout(resolve, 200));
    
    // 3. Verificar se há itens e contatos (com timeout para evitar loop infinito)
    const allStages = stages.value;
    if (Array.isArray(allStages) && allStages.length > 0) {
      // Verificar se há itens nas etapas
      let hasItems = false;
      for (const stage of allStages) {
        if (!stage || !stage.id) continue;
        const items = getItemsForStage(stage.id);
        if (Array.isArray(items) && items.length > 0) {
          hasItems = true;
          break;
        }
      }
      
      // Se não houver itens, não precisa esperar por contatos
      if (!hasItems) {
        isLoadingData.value = false;
        return;
      }
      
      // Aguardar um pouco mais para contatos serem carregados (máximo 1 segundo)
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    
    isLoadingData.value = false;
    } catch (error) {
      console.error('KanbanBoard: Erro ao buscar dados do funil:', error);
    isLoadingData.value = false;
  }
};

onMounted(() => {
  if (props.funnelId) {
    loadData();
  } else {
    isLoadingData.value = false;
  }
});

watch(
  () => props.funnelId,
  (newFunnelId, oldFunnelId) => {
    if (newFunnelId && newFunnelId !== oldFunnelId) {
      loadData();
    } else if (!newFunnelId) {
      isLoadingData.value = false;
      }
    }
);
</script>

<template>
  <div class="kanban-board-container h-full w-full overflow-hidden flex flex-col min-h-0">
      <div v-if="isLoading || isLoadingData" class="flex justify-center items-center h-full bg-n-background">
        <div class="flex flex-col items-center justify-center text-center max-w-sm">
          <div class="relative mb-6">
            <div class="size-16 rounded-full bg-n-teal-3 flex items-center justify-center">
              <Icon icon="i-lucide-loader-2" class="size-8 text-n-teal-9 animate-spin" />
            </div>
            <div class="absolute -inset-1 rounded-full bg-n-teal-6 opacity-20 animate-pulse"></div>
          </div>
          <h3 class="text-lg font-semibold text-n-slate-12 mb-2">{{ t('KANBAN.LOADING') }}</h3>
          <p class="text-sm text-n-slate-10 mb-1">Carregando conversas e contatos...</p>
          <div class="flex items-center gap-1.5 mt-4">
            <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0s"></div>
            <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.2s"></div>
            <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.4s"></div>
          </div>
      </div>
    </div>
    <div
      v-else
      class="kanban-board flex gap-4 p-6 h-full overflow-x-auto overflow-y-hidden items-start"
    >
      <KanbanColumn
        v-for="stage in stages"
        :key="`stage-${stage.id}`"
        :stage="stage"
        :items="getItemsForStage(stage.id)"
        :conversations="conversations"
        @move-item="handleMoveItem"
        @schedule-message="handleScheduleMessage"
        @remove-item="handleRemoveItem"
        @edit-stage="handleEditStage"
        @delete-stage="handleDeleteStage"
      />
      <div
        v-if="stages.length === 0"
        class="flex flex-col items-center justify-center w-full h-full text-n-slate-10 p-8"
      >
        <div class="text-center max-w-md">
          <div class="mb-6 flex justify-center">
            <div class="size-20 rounded-full bg-n-teal-3 flex items-center justify-center">
              <Icon icon="i-lucide-git-branch" class="size-10 text-n-teal-9" />
            </div>
          </div>
          <h3 class="text-xl font-semibold text-n-slate-12 mb-2">{{ t('KANBAN.STAGES.NO_STAGES') }}</h3>
          <p class="text-sm text-n-slate-10 mb-4">{{ t('KANBAN.STAGES.NO_STAGES_DESCRIPTION') }}</p>
          <p class="text-xs text-n-slate-9 italic">{{ t('KANBAN.STAGES.ADD_FIRST_STAGE') }}</p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.kanban-board-container {
  background: var(--n-background);
}

.kanban-board {
  min-width: 100%;
  scrollbar-width: thin;
  scrollbar-color: var(--n-weak) transparent;
}

.kanban-board::-webkit-scrollbar {
  height: 8px;
}

.kanban-board::-webkit-scrollbar-track {
  background: transparent;
}

.kanban-board::-webkit-scrollbar-thumb {
  background-color: var(--n-weak);
  border-radius: 4px;
}

.kanban-board::-webkit-scrollbar-thumb:hover {
  background-color: var(--n-strong);
}
</style>
