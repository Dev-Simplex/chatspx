<script setup>
import { computed, onMounted, watch, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import KanbanColumn from './KanbanColumn.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StageForm from './StageForm.vue';
import draggable from 'vuedraggable';

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

// Estado local para reordenação
const localStages = ref([]);

watch(
  () => stages.value,
  (newStages) => {
    if (Array.isArray(newStages)) {
      localStages.value = [...newStages];
    }
  },
  { immediate: true, deep: true }
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

// Estado para edição de etapa
const showStageForm = ref(false);
const selectedStage = ref(null);

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
      
      // Recarregar os itens do funil para refletir a mudança (sem resolved)
      await store.dispatch('kanban/fetchFunnelItems', {
        funnelId: props.funnelId,
        excludeAutomationType: 'resolved',
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
  console.log('KanbanBoard: handleEditStage recebido:', stage);
  if (!stage) {
    console.error('KanbanBoard: stage é null ou undefined');
    return;
  }
  selectedStage.value = { ...stage }; // Criar cópia para evitar referência
  showStageForm.value = true;
  console.log('KanbanBoard: showStageForm definido como true, selectedStage:', selectedStage.value);
};

const handleStageSaved = async () => {
  // Recarregar etapas e itens após salvar (sem resolved)
  await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
  await store.dispatch('kanban/fetchFunnelItems', {
    funnelId: props.funnelId,
    excludeAutomationType: 'resolved',
  });
  showStageForm.value = false;
  selectedStage.value = null;
};

let isReordering = false;

const handleStageReorder = async (evt) => {
  // Evitar múltiplas chamadas
  if (isReordering) {
    console.log('Reordenação já em andamento, ignorando...');
    return;
  }

  console.log('handleStageReorder chamado:', evt);
  console.log('localStages após drag:', localStages.value.map(s => ({ id: s.id, name: s.name })));
  
  // Verificar se houve mudança de posição
  const hasMoved = evt.moved || 
                   (evt.oldIndex !== undefined && evt.newIndex !== undefined && evt.oldIndex !== evt.newIndex);
  
  if (hasMoved && localStages.value.length > 0) {
    isReordering = true;
    try {
      // Usar a ordem atual do localStages após o drag
      // Garantir que os IDs são números
      const newOrder = localStages.value.map(s => Number(s.id)).filter(id => !isNaN(id));
      console.log('Nova ordem das etapas:', newOrder);
      console.log('FunnelId:', props.funnelId);
      
      if (newOrder.length === 0) {
        console.error('Nenhuma etapa válida para reordenar');
        return;
      }
      
      const result = await store.dispatch('kanban/reorderStages', {
        funnelId: props.funnelId,
        stageIds: newOrder,
      });
      
      console.log('Reordenação enviada ao backend:', result);
      
      // Recarregar etapas para garantir sincronização
      await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
      console.log('Etapas recarregadas após reordenação');
    } catch (error) {
      console.error('Erro ao reordenar etapas:', error);
      console.error('Detalhes do erro:', error.response?.data || error.message);
      
      // Extrair mensagem de erro mais específica
      let errorMessage = 'Erro ao reordenar etapas';
      if (error.response?.data) {
        const errorData = error.response.data;
        if (errorData.details) {
          errorMessage = Array.isArray(errorData.details) 
            ? errorData.details.join(', ')
            : errorData.details;
        } else if (errorData.error) {
          errorMessage = errorData.error;
          if (errorData.details) {
            errorMessage += ': ' + (Array.isArray(errorData.details) ? errorData.details.join(', ') : errorData.details);
          }
        } else if (errorData.message) {
          errorMessage = errorData.message;
        }
      } else if (error.message) {
        errorMessage = error.message;
      }
      
      // Mostrar mensagem de erro mais amigável
      alert(errorMessage);
      
      // Recarregar para reverter visualmente
      await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
    } finally {
      isReordering = false;
    }
  } else {
    console.log('Nenhuma mudança detectada no reordenamento ou localStages vazio');
  }
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
    // 1. Carregar itens do funil (excluindo etapa Resolvidos para performance)
      await store.dispatch('kanban/fetchFunnelItems', {
        funnelId: props.funnelId,
        excludeAutomationType: 'resolved',
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
      class="kanban-board flex gap-5 p-6 h-full overflow-x-auto overflow-y-auto items-stretch bg-gradient-to-br from-n-background via-n-solid-1 to-n-background"
    >
      <draggable
        v-model="localStages"
        :group="{ name: 'kanban-stages', pull: false, put: false }"
        item-key="id"
        handle=".kanban-column-drag-handle"
        class="flex gap-5 h-full items-stretch"
        :animation="200"
        ghost-class="kanban-stage-ghost"
        drag-class="kanban-stage-drag"
        @change="(evt) => { 
          console.log('Draggable change event:', evt); 
          if (evt.moved) {
            console.log('Mudança detectada via change:', evt.moved);
          }
        }"
        @end="handleStageReorder"
      >
        <template #item="{ element: stage }">
          <KanbanColumn
            :key="`stage-${stage.id}`"
            :funnel-id="funnelId"
            :stage="stage"
            :items="getItemsForStage(stage.id)"
            :conversations="conversations"
            @move-item="handleMoveItem"
            @schedule-message="handleScheduleMessage"
            @remove-item="handleRemoveItem"
            @edit-stage="handleEditStage"
            @delete-stage="handleDeleteStage"
          />
        </template>
      </draggable>
      <div
        v-if="stages.length === 0"
        class="flex flex-col items-center justify-center w-full h-full text-n-slate-10 p-8"
      >
        <div class="text-center max-w-lg px-6">
          <div class="mb-8 flex justify-center">
            <div class="relative">
              <div class="size-24 rounded-2xl bg-gradient-to-br from-n-teal-4 to-n-blue-4 flex items-center justify-center shadow-lg border-2 border-n-teal-6">
                <Icon icon="i-lucide-git-branch" class="size-12 text-n-teal-9" />
              </div>
              <div class="absolute -top-2 -right-2 size-8 rounded-full bg-n-blue-5 border-2 border-n-background flex items-center justify-center">
                <Icon icon="i-lucide-plus" class="size-4 text-n-blue-9" />
              </div>
            </div>
          </div>
          <h3 class="text-2xl font-bold text-n-slate-12 mb-3">{{ t('KANBAN.STAGES.NO_STAGES') }}</h3>
          <p class="text-base text-n-slate-11 mb-2 leading-relaxed">{{ t('KANBAN.STAGES.NO_STAGES_DESCRIPTION') }}</p>
          <p class="text-sm text-n-slate-10 mb-6">{{ t('KANBAN.STAGES.ADD_FIRST_STAGE') }}</p>
          <div class="flex items-center justify-center gap-2 text-xs text-n-slate-9">
            <Icon icon="i-lucide-info" class="size-4" />
            <span>Edite o funil para adicionar etapas</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Stage Form Modal -->
    <StageForm
      :show="showStageForm && !!selectedStage"
      :stage="selectedStage"
      :funnel-id="funnelId"
      @close="() => { showStageForm = false; selectedStage = null; }"
      @saved="handleStageSaved"
    />
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

:deep(.kanban-stage-ghost) {
  opacity: 0.5;
  transform: rotate(2deg);
}

:deep(.kanban-stage-drag) {
  opacity: 0.9;
  transform: scale(1.02);
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
}
</style>
