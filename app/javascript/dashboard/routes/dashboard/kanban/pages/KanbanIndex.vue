<script setup>
import { onMounted, computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import KanbanBoard from 'dashboard/components-next/Kanban/KanbanBoard.vue';
import ListView from 'dashboard/components-next/Kanban/ListView.vue';
import CalendarView from 'dashboard/components-next/Kanban/CalendarView.vue';
import FunnelForm from 'dashboard/components-next/Kanban/FunnelForm.vue';
import ScheduledMessageForm from 'dashboard/components-next/Kanban/ScheduledMessageForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const funnels = computed(() => store.getters['kanban/getFunnels']);
const activeFunnelId = computed(() => store.getters['kanban/getActiveFunnelId']);
const viewMode = computed(() => store.getters['kanban/getViewMode']);

const showFunnelForm = ref(false);
const showScheduledMessageForm = ref(false);
const selectedFunnel = ref(null);
const selectedConversation = ref(null);

const activeFunnel = computed(() => {
  if (!activeFunnelId.value) return null;
  return funnels.value.find(f => f.id === activeFunnelId.value);
});

const activeFunnelStagesCount = computed(() => {
  if (!activeFunnelId.value) return 0;
  return store.getters['kanban/getFunnelStages'](activeFunnelId.value)?.length || 0;
});

const activeFunnelTotalItems = computed(() => {
  if (!activeFunnelId.value) return 0;
  const stages = store.getters['kanban/getFunnelStages'](activeFunnelId.value);
  if (!Array.isArray(stages)) return 0;
  let total = 0;
  stages.forEach(stage => {
    if (stage && stage.id) {
      const items = store.getters['kanban/getFunnelItems'](activeFunnelId.value, stage.id);
      if (Array.isArray(items)) {
        total += items.length;
      }
    }
  });
  return total;
});

onMounted(async () => {
  // Garantir que o viewMode está inicializado
  const currentViewMode = store.getters['kanban/getViewMode'];
  if (!currentViewMode) {
    store.dispatch('kanban/setViewMode', 'kanban');
  }
  
  await store.dispatch('kanban/fetchFunnels');
  
  const availableFunnels = funnels.value;
  
  if (route.params.funnelId) {
    const funnelId = parseInt(route.params.funnelId);
    // Verificar se o funil existe e é acessível
    const funnel = availableFunnels.find(f => f.id === funnelId);
    if (funnel) {
      store.dispatch('kanban/setActiveFunnelId', funnelId);
      await store.dispatch('kanban/fetchFunnelStages', funnelId);
      await store.dispatch('kanban/fetchFunnelItems', { funnelId, excludeAutomationType: 'resolved' });
    } else {
      // Funil não encontrado ou não acessível, redirecionar para o primeiro
      if (availableFunnels.length > 0) {
        const firstFunnelId = availableFunnels[0].id;
        store.dispatch('kanban/setActiveFunnelId', firstFunnelId);
        await store.dispatch('kanban/fetchFunnelStages', firstFunnelId);
        await store.dispatch('kanban/fetchFunnelItems', { funnelId: firstFunnelId, excludeAutomationType: 'resolved' });
        router.replace({
          name: 'kanban_funnel',
          params: { funnelId: firstFunnelId },
        });
      }
    }
  } else if (availableFunnels.length > 0) {
    // Sem funilId na rota, redirecionar para o primeiro funil disponível
    const firstFunnelId = availableFunnels[0].id;
    store.dispatch('kanban/setActiveFunnelId', firstFunnelId);
    await store.dispatch('kanban/fetchFunnelStages', firstFunnelId);
    await store.dispatch('kanban/fetchFunnelItems', { funnelId: firstFunnelId, excludeAutomationType: 'resolved' });
    router.replace({
      name: 'kanban_funnel',
      params: { funnelId: firstFunnelId },
    });
  }
});


const handleFunnelSelect = async (funnelId) => {
  store.dispatch('kanban/setActiveFunnelId', funnelId);
  // Buscar etapas do funil selecionado
  await store.dispatch('kanban/fetchFunnelStages', funnelId);
  await store.dispatch('kanban/fetchFunnelItems', { funnelId });
  router.push({
    name: 'kanban_funnel',
    params: { funnelId },
  });
};

const handleCreateFunnel = () => {
  selectedFunnel.value = null;
  showFunnelForm.value = true;
};

const handleEditFunnel = (funnel) => {
  selectedFunnel.value = funnel;
  showFunnelForm.value = true;
};

const handleFunnelSaved = async () => {
  // Buscar funis atualizados
  await store.dispatch('kanban/fetchFunnels');
  
  // Aguardar um pouco para garantir que o store foi atualizado
  await new Promise(resolve => setTimeout(resolve, 100));
  
  // Buscar etapas do funil recém-criado ou editado
  const updatedFunnels = store.getters['kanban/getFunnels'];
  if (updatedFunnels.length > 0) {
    // Se estava editando, usar o funil editado, senão usar o último criado
    let targetFunnel = selectedFunnel.value 
      ? updatedFunnels.find(f => f.id === selectedFunnel.value.id)
      : updatedFunnels[updatedFunnels.length - 1];
    
    if (targetFunnel) {
      // Buscar etapas do funil
      await store.dispatch('kanban/fetchFunnelStages', targetFunnel.id);
      await store.dispatch('kanban/fetchFunnelItems', { funnelId: targetFunnel.id, excludeAutomationType: 'resolved' });
      // Selecionar o funil
      store.dispatch('kanban/setActiveFunnelId', targetFunnel.id);
      // Atualizar rota
      router.push({
        name: 'kanban_funnel',
        params: { funnelId: targetFunnel.id },
      });
    }
  }
  
  selectedFunnel.value = null;
  showFunnelForm.value = false;
};

const selectedDate = ref(null);
const requireConversationForModal = ref(true);

const handleScheduleMessage = (conversation) => {
  selectedConversation.value = conversation;
  selectedDate.value = null;
  requireConversationForModal.value = true;
  showScheduledMessageForm.value = true;
};

const handleScheduledMessageSaved = () => {
  showScheduledMessageForm.value = false;
  selectedConversation.value = null;
  selectedDate.value = null;
  // Recarregar mensagens agendadas após salvar
  store.dispatch('kanban/fetchScheduledMessages');
};

const handleCreateScheduledMessageFromCalendar = (date) => {
  // Não há conversation no calendário, usuário precisa selecionar
  selectedConversation.value = null;
  selectedDate.value = date;
  requireConversationForModal.value = false;
  showScheduledMessageForm.value = true;
};

const setViewMode = async (mode) => {
  console.log('KanbanIndex: Mudando viewMode para:', mode);
  store.dispatch('kanban/setViewMode', mode);
  
  // Recarregar dados quando mudar para lista para garantir que está atualizado
  if (mode === 'list' && activeFunnelId.value) {
    console.log('KanbanIndex: Recarregando dados para visualização de lista...');
    try {
      await store.dispatch('kanban/fetchFunnelStages', activeFunnelId.value);
      await store.dispatch('kanban/fetchFunnelItems', {
        funnelId: activeFunnelId.value,
        excludeAutomationType: 'resolved',
      });
      console.log('KanbanIndex: Dados recarregados para lista');
    } catch (error) {
      console.error('KanbanIndex: Erro ao recarregar dados:', error);
    }
  }
};
</script>

<template>
  <div class="kanban-container flex flex-col overflow-hidden">
    <!-- Header -->
    <div class="kanban-header relative flex items-center justify-between px-6 py-5 border-b border-n-weak bg-gradient-to-r from-n-solid-2 to-n-solid-3 shadow-md flex-shrink-0">
      <!-- Left Section: Title and Funnel Selection -->
      <div class="flex items-center gap-6 flex-1 min-w-0">
        <div class="flex items-center gap-3 flex-shrink-0">
          <div class="flex items-center justify-center size-10 rounded-lg bg-n-teal-4 border border-n-teal-6">
            <Icon icon="i-lucide-layout-grid" class="size-5 text-n-teal-9" />
          </div>
          <h1 class="text-2xl font-bold text-n-slate-12 whitespace-nowrap">
            {{ t('KANBAN.TITLE') }}
          </h1>
        </div>
        
        <div v-if="funnels.length > 0" class="flex items-center gap-4 flex-1 min-w-0">
          <!-- Funnel Selector -->
          <div class="relative flex-shrink-0">
            <div class="flex items-center gap-2 px-1">
              <Icon icon="i-lucide-filter" class="size-4 text-n-slate-10 flex-shrink-0" />
              <span class="text-xs text-n-slate-11 font-medium whitespace-nowrap">{{ t('KANBAN.FILTER_BY_FUNNEL') }}</span>
            </div>
            <div class="relative mt-1.5">
              <select
                :value="activeFunnelId || ''"
                class="pl-10 pr-8 py-2.5 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 font-medium min-w-[280px] focus:outline-none focus:ring-2 focus:ring-n-blue-9 focus:border-n-blue-9 appearance-none cursor-pointer hover:bg-n-solid-4 transition-all shadow-sm"
                style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none;"
                @change="handleFunnelSelect(parseInt($event.target.value))"
              >
                <option value="" disabled>{{ t('KANBAN.SELECT_FUNNEL') }}</option>
                <option
                  v-for="funnel in funnels"
                  :key="funnel.id"
                  :value="funnel.id"
                >
                  {{ funnel.name }}
                </option>
              </select>
              <div 
                v-if="activeFunnel && activeFunnel.color"
                class="absolute left-3 top-1/2 -translate-y-1/2 size-3 rounded-full border border-n-weak shadow-sm"
                :style="{ backgroundColor: activeFunnel.color }"
              ></div>
              <div class="absolute right-2.5 top-0 bottom-0 flex items-center pointer-events-none">
                <Icon icon="i-lucide-chevron-down" class="size-4 text-n-slate-9" />
              </div>
            </div>
          </div>
          
          <!-- Statistics -->
          <div v-if="activeFunnel" class="flex items-center gap-4 flex-shrink-0 ml-2">
            <div class="flex items-center gap-2 px-3 py-1.5 bg-n-solid-3 rounded-lg border border-n-weak">
              <Icon icon="i-lucide-git-branch" class="size-4 text-n-teal-9" />
              <span class="text-sm font-semibold text-n-slate-12">{{ activeFunnelStagesCount }}</span>
              <span class="text-xs text-n-slate-10">{{ t('KANBAN.STAGES.TITLE') }}</span>
            </div>
            <div class="flex items-center gap-2 px-3 py-1.5 bg-n-solid-3 rounded-lg border border-n-weak">
              <Icon icon="i-lucide-message-square" class="size-4 text-n-blue-9" />
              <span class="text-sm font-semibold text-n-slate-12">{{ activeFunnelTotalItems }}</span>
              <span class="text-xs text-n-slate-10">itens</span>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Right Section: View Toggle and Actions -->
      <div class="flex items-center gap-3 flex-shrink-0 ml-4">
        <!-- View Mode Toggle -->
        <div class="flex gap-1 bg-n-solid-3 rounded-lg p-1 border border-n-weak shadow-sm">
          <Button
            :variant="viewMode === 'kanban' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-layout-grid"
            :title="t('KANBAN.VIEWS.KANBAN') + ' - Visualização em colunas'"
            class="!px-3 transition-all"
            @click="setViewMode('kanban')"
          />
          <Button
            :variant="viewMode === 'list' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-list"
            :title="t('KANBAN.VIEWS.LIST') + ' - Visualização em lista'"
            class="!px-3 transition-all"
            @click="setViewMode('list')"
          />
          <Button
            :variant="viewMode === 'calendar' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-calendar"
            :title="t('KANBAN.VIEWS.CALENDAR') + ' - Visualização em calendário'"
            class="!px-3 transition-all"
            @click="setViewMode('calendar')"
          />
        </div>
        <!-- Actions -->
        <div class="flex items-center gap-2 border-l border-n-weak pl-3">
          <Button
            v-if="activeFunnel"
            variant="ghost"
            size="sm"
            icon="i-lucide-edit"
            :title="t('KANBAN.FUNNELS.EDIT') + ' - Editar funil atual'"
            class="transition-all"
            @click="handleEditFunnel(activeFunnel)"
          >
            <span class="ml-2 hidden sm:inline">{{ t('KANBAN.FUNNELS.EDIT') }}</span>
          </Button>
          <Button
            icon="i-lucide-plus"
            color="blue"
            size="sm"
            :title="t('KANBAN.FUNNELS.CREATE') + ' - Criar novo funil'"
            class="transition-all shadow-sm hover:shadow-md"
            @click="handleCreateFunnel"
          >
            <span class="ml-2 hidden sm:inline">{{ t('KANBAN.FUNNELS.CREATE') }}</span>
          </Button>
        </div>
      </div>
    </div>

    <!-- Content Area - Full Height -->
    <div class="kanban-content flex-1 min-h-0 overflow-hidden bg-n-background">
      <!-- Empty State -->
      <div
        v-if="!activeFunnelId && funnels.length === 0"
        class="flex flex-col items-center justify-center h-full bg-gradient-to-br from-n-background via-n-solid-1 to-n-background"
      >
        <div class="text-center max-w-lg px-6">
          <div class="mb-8 flex justify-center">
            <div class="relative">
              <div class="size-24 rounded-2xl bg-gradient-to-br from-n-teal-4 to-n-blue-4 flex items-center justify-center shadow-lg border-2 border-n-teal-6">
                <Icon icon="i-lucide-layout-grid" class="size-12 text-n-teal-9" />
              </div>
              <div class="absolute -top-2 -right-2 size-8 rounded-full bg-n-blue-5 border-2 border-n-background flex items-center justify-center">
                <Icon icon="i-lucide-sparkles" class="size-4 text-n-blue-9" />
              </div>
            </div>
          </div>
          <h2 class="text-3xl font-bold text-n-slate-12 mb-3">
            {{ t('KANBAN.FUNNELS.NO_FUNNELS') }}
          </h2>
          <p class="text-base text-n-slate-11 mb-8 leading-relaxed">
            {{ t('KANBAN.FUNNELS.NO_FUNNELS_DESCRIPTION') }}
          </p>
          <Button
            icon="i-lucide-plus"
            color="blue"
            size="lg"
            class="shadow-lg hover:shadow-xl transition-shadow"
            @click="handleCreateFunnel"
          >
            <span class="ml-2 font-semibold">{{ t('KANBAN.FUNNELS.CREATE') }}</span>
          </Button>
        </div>
      </div>

      <!-- Select Funnel State -->
      <div
        v-else-if="!activeFunnelId"
        class="flex items-center justify-center h-full bg-gradient-to-br from-n-background via-n-solid-1 to-n-background"
      >
        <div class="text-center max-w-md px-6">
          <div class="mb-6 flex justify-center">
            <div class="size-16 rounded-xl bg-n-teal-3 border-2 border-n-teal-6 flex items-center justify-center">
              <Icon icon="i-lucide-arrow-down-circle" class="size-8 text-n-teal-9 animate-bounce" />
            </div>
          </div>
          <h3 class="text-xl font-semibold text-n-slate-12 mb-2">{{ t('KANBAN.SELECT_FUNNEL') }}</h3>
          <p class="text-sm text-n-slate-10">Selecione um funil no menu acima para começar</p>
        </div>
      </div>

      <!-- Views - Only show when there's an active funnel -->
      <template v-if="activeFunnelId">
        <!-- Kanban View -->
        <KanbanBoard
          v-if="viewMode === 'kanban'"
          :key="`kanban-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
        />

        <!-- List View -->
        <ListView
          v-else-if="viewMode === 'list'"
          :key="`list-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
        />

        <!-- Calendar View -->
        <CalendarView
          v-else-if="viewMode === 'calendar'"
          :key="`calendar-${activeFunnelId}-${viewMode}`"
          :funnel-id="activeFunnelId"
          @schedule-message="handleScheduleMessage"
          @create-scheduled-message="handleCreateScheduledMessageFromCalendar"
        />
      </template>
    </div>

    <!-- Modals -->
    <FunnelForm
      :show="showFunnelForm"
      :funnel="selectedFunnel"
      @close="showFunnelForm = false"
      @saved="handleFunnelSaved"
    />
    <ScheduledMessageForm
      :show="showScheduledMessageForm"
      :conversation="selectedConversation"
      :require-conversation="requireConversationForModal"
      :funnel-id="activeFunnelId"
      :selected-date="selectedDate"
      @close="showScheduledMessageForm = false"
      @saved="handleScheduledMessageSaved"
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
</style>
