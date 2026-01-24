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
import Icon from 'next/icon/Icon.vue';

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
      await store.dispatch('kanban/fetchFunnelItems', { funnelId });
    } else {
      // Funil não encontrado ou não acessível, redirecionar para o primeiro
      if (availableFunnels.length > 0) {
        const firstFunnelId = availableFunnels[0].id;
        store.dispatch('kanban/setActiveFunnelId', firstFunnelId);
        await store.dispatch('kanban/fetchFunnelStages', firstFunnelId);
        await store.dispatch('kanban/fetchFunnelItems', { funnelId: firstFunnelId });
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
    await store.dispatch('kanban/fetchFunnelItems', { funnelId: firstFunnelId });
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
      await store.dispatch('kanban/fetchFunnelItems', { funnelId: targetFunnel.id });
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
    <div class="kanban-header flex items-center justify-between px-6 py-4 border-b border-n-weak bg-n-solid-2 shadow-sm flex-shrink-0">
      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <Icon icon="i-lucide-layout-grid" class="size-6 text-n-teal-9" />
          <h1 class="text-2xl font-bold text-n-slate-12">
            {{ t('KANBAN.TITLE') }}
          </h1>
        </div>
        <div v-if="funnels.length > 0" class="flex items-center gap-3">
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-filter" class="size-4 text-n-slate-10" />
            <span class="text-sm text-n-slate-11 font-medium">{{ t('KANBAN.FILTER_BY_FUNNEL') }}</span>
          </div>
          <div class="relative">
            <select
              :value="activeFunnelId || ''"
              class="px-4 py-2 pr-8 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 font-medium min-w-[250px] focus:outline-none focus:ring-2 focus:ring-n-blue-9 appearance-none cursor-pointer hover:bg-n-solid-4 transition-colors"
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
            <div class="absolute right-2.5 top-0 bottom-0 flex items-center pointer-events-none">
            <Icon
              icon="i-lucide-chevron-down"
                class="size-4 text-n-slate-9"
            />
            </div>
          </div>
          <div v-if="activeFunnel" class="flex items-center gap-2 text-sm text-n-slate-10">
            <Icon icon="i-lucide-git-branch" class="size-4" />
            <span>{{ activeFunnelStagesCount }} {{ t('KANBAN.STAGES.TITLE') }}</span>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <!-- View Mode Toggle -->
        <div class="flex gap-1 bg-n-solid-3 rounded-lg p-1 border border-n-weak">
          <Button
            :variant="viewMode === 'kanban' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-layout-grid"
            :title="t('KANBAN.VIEWS.KANBAN')"
            class="!px-3"
            @click="setViewMode('kanban')"
          />
          <Button
            :variant="viewMode === 'list' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-list"
            :title="t('KANBAN.VIEWS.LIST')"
            class="!px-3"
            @click="setViewMode('list')"
          />
          <Button
            :variant="viewMode === 'calendar' ? 'solid' : 'ghost'"
            size="sm"
            icon="i-lucide-calendar"
            :title="t('KANBAN.VIEWS.CALENDAR')"
            class="!px-3"
            @click="setViewMode('calendar')"
          />
        </div>
        <!-- Actions -->
        <div class="flex items-center gap-2">
          <Button
            v-if="activeFunnel"
            variant="ghost"
            icon="i-lucide-edit"
            @click="handleEditFunnel(activeFunnel)"
          >
            <span class="ml-2">{{ t('KANBAN.FUNNELS.EDIT') }}</span>
          </Button>
          <Button
            icon="i-lucide-plus"
            color="blue"
            @click="handleCreateFunnel"
          >
            <span class="ml-2">{{ t('KANBAN.FUNNELS.CREATE') }}</span>
          </Button>
        </div>
      </div>
    </div>

    <!-- Content Area - Full Height -->
    <div class="kanban-content flex-1 min-h-0 overflow-hidden bg-n-background">
      <!-- Empty State -->
      <div
        v-if="!activeFunnelId && funnels.length === 0"
        class="flex flex-col items-center justify-center h-full"
      >
        <div class="text-center max-w-md">
          <div class="mb-6 flex justify-center">
            <div class="size-20 rounded-full bg-n-teal-3 flex items-center justify-center">
              <Icon icon="i-lucide-layout-grid" class="size-10 text-n-teal-9" />
            </div>
          </div>
          <h2 class="text-2xl font-semibold text-n-slate-12 mb-2">
            {{ t('KANBAN.FUNNELS.NO_FUNNELS') }}
          </h2>
          <p class="text-n-slate-10 mb-6">
            {{ t('KANBAN.FUNNELS.NO_FUNNELS_DESCRIPTION') }}
          </p>
          <Button
            icon="i-lucide-plus"
            color="blue"
            size="lg"
            @click="handleCreateFunnel"
          >
            <span class="ml-2">{{ t('KANBAN.FUNNELS.CREATE') }}</span>
          </Button>
        </div>
      </div>

      <!-- Select Funnel State -->
      <div
        v-else-if="!activeFunnelId"
        class="flex items-center justify-center h-full"
      >
        <div class="text-center">
          <Icon icon="i-lucide-arrow-down-circle" class="size-12 text-n-slate-10 mx-auto mb-4" />
          <p class="text-lg text-n-slate-10">{{ t('KANBAN.SELECT_FUNNEL') }}</p>
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
