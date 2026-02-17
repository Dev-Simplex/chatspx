<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format, startOfMonth, endOfMonth, eachDayOfInterval, isSameDay, startOfWeek, endOfWeek } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits([
  'schedule-message',
  'create-scheduled-message',
  'edit-scheduled-message',
  'cancel-scheduled-message',
]);

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const currentDate = ref(new Date());
const selectedDate = ref(null);
const showDayDialog = ref(false);
const selectedDayMessages = ref([]);
const selectedDayDate = ref(null);

const scheduledMessages = computed(() =>
  store.getters['kanban/getScheduledMessages']
);

const isLoading = computed(() => store.getters['kanban/getUIFlags'].isFetching);

// Estado de loading robusto que aguarda todos os dados
const isLoadingData = ref(true);

const monthStart = computed(() => startOfMonth(currentDate.value));
const monthEnd = computed(() => endOfMonth(currentDate.value));
const weekStart = computed(() => startOfWeek(monthStart.value, { locale: ptBR }));
const weekEnd = computed(() => endOfWeek(monthEnd.value, { locale: ptBR }));

const daysInMonth = computed(() =>
  eachDayOfInterval({ start: weekStart.value, end: weekEnd.value })
);

const getMessagesForDate = (date) => {
  return scheduledMessages.value
    .filter(msg => isSameDay(new Date(msg.scheduledAt), date))
    .sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));
};

const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const getConversationFromStore = (conversationId) => {
  if (!conversationId || !getConversationById.value) return null;
  return getConversationById.value(conversationId);
};

const getContactFromConversation = (conversation) => {
  return conversation?.meta?.sender || conversation?.contact || {};
};

const getContactInfoForMessage = (message) => {
  const conversation = getConversationFromStore(message.conversationId);
  const contact = getContactFromConversation(conversation);
  return {
    name: contact?.name || `Conversa #${message.conversationId || message.id}`,
    phone: contact?.phone_number || contact?.phoneNumber || contact?.identifier || '',
    avatar: contact?.thumbnail || contact?.avatar_url || contact?.avatar || '',
  };
};

const getMessageStatusLabel = (status) => {
  const labels = {
    pending: 'Pendente',
    sent: 'Enviada',
    failed: 'Falhou',
    cancelled: 'Cancelada',
  };
  return labels[status] || 'Agendada';
};

const getMessageStatusClass = (status) => {
  const classes = {
    pending: 'bg-n-teal-9 hover:bg-n-teal-10',
    sent: 'bg-n-emerald-9 hover:bg-n-emerald-10',
    failed: 'bg-n-ruby-9 hover:bg-n-ruby-10',
    cancelled: 'bg-n-slate-8 hover:bg-n-slate-9',
  };
  return classes[status] || 'bg-n-teal-9 hover:bg-n-teal-10';
};

const canManageMessage = message => message?.status === 'pending';

const handleEditScheduledMessage = message => {
  if (!canManageMessage(message)) return;
  emit('edit-scheduled-message', message);
};

const handleCancelScheduledMessage = message => {
  if (!canManageMessage(message)) return;
  emit('cancel-scheduled-message', message);
};

const openConversation = async (message) => {
  if (!message?.conversationId && !message?.conversationDisplayId) {
    useAlert('Conversa não encontrada.');
    return;
  }

  const conversationId =
    message.conversationDisplayId ||
    getConversationFromStore(message.conversationId)?.displayId ||
    getConversationFromStore(message.conversationId)?.display_id ||
    message.conversationId;

  if (!conversationId) {
    useAlert('Conversa não encontrada.');
    return;
  }

  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};

const previousMonth = () => {
  currentDate.value = new Date(
    currentDate.value.getFullYear(),
    currentDate.value.getMonth() - 1,
    1
  );
};

const nextMonth = () => {
  currentDate.value = new Date(
    currentDate.value.getFullYear(),
    currentDate.value.getMonth() + 1,
    1
  );
};

const isCurrentMonth = (date) => {
  return date.getMonth() === currentDate.value.getMonth();
};

const handleDateClick = (date) => {
  selectedDate.value = date;
  const dayMessages = getMessagesForDate(date);
  if (dayMessages.length > 0) {
    selectedDayMessages.value = dayMessages;
    selectedDayDate.value = date;
    showDayDialog.value = true;
    return;
  }

  // Emitir evento para criar mensagem agendada nesta data
  emit('create-scheduled-message', date);
};

const handleScheduleFromDay = () => {
  if (!selectedDayDate.value) return;
  showDayDialog.value = false;
  emit('create-scheduled-message', selectedDayDate.value);
};

const loadData = async () => {
  if (!props.funnelId) {
    isLoadingData.value = false;
    return;
  }
  
  isLoadingData.value = true;
  
  try {
    // 1. Carregar mensagens agendadas
  await store.dispatch('kanban/fetchScheduledMessages');
    
    // 2. Aguardar um pouco para garantir que os dados estão no store
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // 3. Verificar se contatos estão disponíveis nas mensagens agendadas
    const messages = scheduledMessages.value;
    if (Array.isArray(messages)) {
      const loadPromises = messages.map(async (message) => {
        if (message.conversationId) {
          const getConversationById = store.getters['conversations/getConversationById'];
          if (getConversationById) {
            const conversation = getConversationById(message.conversationId);
            if (conversation && conversation.contactId) {
              const getContactById = store.getters['contacts/getContactById'];
              if (getContactById) {
                const contact = getContactById(conversation.contactId);
                // Se o contato não estiver carregado, aguardar um pouco
                if (!contact) {
                  await new Promise(resolve => setTimeout(resolve, 50));
                }
              }
            }
          }
        }
      });
      
      await Promise.all(loadPromises);
    }
    
    // 4. Aguardar mais um pouco para garantir que tudo está renderizado
    await new Promise(resolve => setTimeout(resolve, 100));
    
    isLoadingData.value = false;
  } catch (error) {
    console.error('CalendarView: Erro ao carregar dados:', error);
    isLoadingData.value = false;
  }
};

onMounted(() => {
  loadData();
});
</script>

<template>
  <div class="calendar-view-container h-full w-full overflow-auto p-6 bg-gradient-to-br from-n-background via-n-solid-1 to-n-background">
    <div v-if="isLoading || isLoadingData" class="flex justify-center items-center h-full bg-n-background">
      <div class="flex flex-col items-center justify-center text-center max-w-sm">
        <div class="relative mb-6">
          <div class="size-16 rounded-full bg-n-teal-3 flex items-center justify-center">
            <Icon icon="i-lucide-loader-2" class="size-8 text-n-teal-9 animate-spin" />
          </div>
          <div class="absolute -inset-1 rounded-full bg-n-teal-6 opacity-20 animate-pulse"></div>
        </div>
        <h3 class="text-lg font-semibold text-n-slate-12 mb-2">{{ t('KANBAN.LOADING') }}</h3>
        <p class="text-sm text-n-slate-10 mb-1">Carregando mensagens agendadas...</p>
        <div class="flex items-center gap-1.5 mt-4">
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0s"></div>
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.2s"></div>
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.4s"></div>
        </div>
      </div>
    </div>
    <div v-else class="calendar-wrapper max-w-7xl mx-auto">
      <!-- Calendar Header -->
      <div class="calendar-header flex items-center justify-between mb-6 p-4 bg-gradient-to-r from-n-solid-2 to-n-solid-3 rounded-xl border border-n-weak shadow-sm">
        <Button
          variant="ghost"
          icon="i-lucide-chevron-left"
          class="hover:bg-n-solid-4 transition-colors"
          @click="previousMonth"
        />
        <div class="flex items-center gap-3">
          <div class="flex items-center justify-center size-10 rounded-lg bg-n-teal-4 border border-n-teal-6">
            <Icon icon="i-lucide-calendar" class="size-5 text-n-teal-9" />
          </div>
          <h2 class="text-2xl font-bold text-n-slate-12">
            {{ format(currentDate, 'MMMM yyyy', { locale: ptBR }) }}
          </h2>
        </div>
        <div class="flex items-center gap-2">
          <Button
            variant="ghost"
            icon="i-lucide-chevron-right"
            class="hover:bg-n-solid-4 transition-colors"
            @click="nextMonth"
          />
          <Button
            color="blue"
            icon="i-lucide-plus"
            class="shadow-sm hover:shadow-md transition-shadow"
            @click="handleDateClick(new Date())"
          >
            <span class="ml-2 font-semibold">{{ t('KANBAN.SCHEDULED_MESSAGES.CREATE') }}</span>
          </Button>
        </div>
      </div>

      <!-- Calendar Grid -->
      <div class="calendar-grid bg-n-solid-2 rounded-xl border border-n-weak overflow-visible shadow-lg">
        <!-- Week Days Header -->
        <div class="grid grid-cols-7 border-b-2 border-n-weak bg-gradient-to-r from-n-solid-3 to-n-solid-2">
          <div
            v-for="day in ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']"
            :key="day"
            class="text-center text-sm font-bold text-n-slate-12 p-4 border-r border-n-weak last:border-r-0"
          >
            {{ day }}
          </div>
        </div>

        <!-- Calendar Days -->
        <div class="grid grid-cols-7">
          <div
            v-for="(day, index) in daysInMonth"
            :key="index"
            :class="[
              'calendar-day p-3 min-h-[120px] border-r border-b border-n-weak last:border-r-0 bg-n-solid-2 transition-all duration-200',
              !isCurrentMonth(day) ? 'opacity-40' : '',
              isSameDay(day, new Date()) ? 'bg-n-teal-3 ring-2 ring-n-teal-6' : '',
              selectedDate && isSameDay(day, selectedDate) ? 'selected-day' : '',
              'hover:bg-n-solid-3 hover:shadow-inner cursor-pointer',
            ]"
            @click="handleDateClick(day)"
          >
            <div class="flex items-center justify-between mb-2">
              <span
                :class="[
                  'text-sm font-medium',
                  isSameDay(day, new Date()) ? 'text-n-teal-9' : 'text-n-slate-12',
                ]"
              >
                {{ format(day, 'd') }}
              </span>
              <span
                v-if="getMessagesForDate(day).length > 0"
                class="text-xs bg-n-teal-9 text-white px-2 py-0.5 rounded-full font-medium"
              >
                {{ getMessagesForDate(day).length }}
              </span>
            </div>
            <div class="space-y-1.5">
              <button
                v-for="message in getMessagesForDate(day)"
                :key="message.id"
                type="button"
                class="w-full text-left text-xs text-white p-2.5 rounded-lg border border-white/20 shadow-sm transition-all duration-200 flex items-start gap-2 hover:shadow-md hover:scale-[1.02]"
                :class="getMessageStatusClass(message.status)"
                :title="message.message"
                @click.stop="openConversation(message)"
              >
                <Avatar
                  :src="getContactInfoForMessage(message).avatar"
                  :name="getContactInfoForMessage(message).name"
                  :size="28"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <Icon icon="i-lucide-clock" class="size-3 flex-shrink-0" />
                    <span class="text-xs font-semibold">
                      {{ format(new Date(message.scheduledAt), 'HH:mm') }}
                    </span>
                    <span class="text-[10px] uppercase tracking-wide text-white/80">
                      {{ getMessageStatusLabel(message.status) }}
                    </span>
                  </div>
                  <div class="text-xs font-medium truncate">
                    {{ getContactInfoForMessage(message).name }}
                  </div>
                  <div
                    v-if="getContactInfoForMessage(message).phone"
                    class="text-[10px] text-white/80 font-mono truncate"
                  >
                    {{ getContactInfoForMessage(message).phone }}
                  </div>
                  <div class="text-[10px] text-white/80 truncate">
                    {{ message.message }}
                  </div>
                  <div
                    v-if="canManageMessage(message)"
                    class="mt-1 flex items-center justify-end gap-1"
                    @click.stop
                  >
                    <Button
                      size="xs"
                      variant="ghost"
                      icon="i-lucide-pencil"
                      class="!h-6 !w-6 !p-0 !text-white hover:!bg-white/20"
                      :title="t('KANBAN.SCHEDULED_MESSAGES.EDIT')"
                      @click.stop="handleEditScheduledMessage(message)"
                    />
                    <Button
                      size="xs"
                      variant="ghost"
                      icon="i-lucide-trash-2"
                      class="!h-6 !w-6 !p-0 !text-white hover:!bg-white/20"
                      :title="t('KANBAN.SCHEDULED_MESSAGES.CANCEL')"
                      @click.stop="handleCancelScheduledMessage(message)"
                    />
                  </div>
                </div>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      v-if="showDayDialog"
      :show="showDayDialog"
      :title="t('KANBAN.SCHEDULED_MESSAGES.DAY_TITLE', { date: format(selectedDayDate || new Date(), 'dd MMMM yyyy', { locale: ptBR }) })"
      :show-cancel-button="false"
      :show-confirm-button="false"
      overflow-y-auto
      width="xl"
      @close="showDayDialog = false"
    >
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div class="text-sm text-n-slate-10">
            {{ t('KANBAN.SCHEDULED_MESSAGES.DAY_COUNT', { count: selectedDayMessages.length }) }}
          </div>
          <Button
            color="blue"
            icon="i-lucide-plus"
            size="sm"
            @click="handleScheduleFromDay"
          >
            <span class="ml-2">{{ t('KANBAN.SCHEDULED_MESSAGES.SCHEDULE') }}</span>
          </Button>
        </div>

        <div class="space-y-2">
          <button
            v-for="message in selectedDayMessages"
            :key="message.id"
            type="button"
            class="w-full text-left p-3 rounded-lg border border-n-weak bg-n-solid-3 hover:bg-n-solid-4 transition-colors flex items-start gap-3"
            @click="openConversation(message)"
          >
            <Avatar
              :src="getContactInfoForMessage(message).avatar"
              :name="getContactInfoForMessage(message).name"
              :size="36"
            />
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <Icon icon="i-lucide-clock" class="size-3 text-n-slate-11" />
                <span class="text-xs font-semibold text-n-slate-12">
                  {{ format(new Date(message.scheduledAt), 'HH:mm') }}
                </span>
                <span class="text-[10px] uppercase tracking-wide text-n-slate-11">
                  {{ getMessageStatusLabel(message.status) }}
                </span>
              </div>
              <div class="text-sm font-medium text-n-slate-12 truncate">
                {{ getContactInfoForMessage(message).name }}
              </div>
              <div
                v-if="getContactInfoForMessage(message).phone"
                class="text-xs text-n-slate-10 font-mono truncate"
              >
                {{ getContactInfoForMessage(message).phone }}
              </div>
              <div class="text-xs text-n-slate-11 truncate">
                {{ message.message || t('KANBAN.SCHEDULED_MESSAGES.NO_TEXT') }}
              </div>
              <div
                v-if="canManageMessage(message)"
                class="mt-2 flex items-center justify-end gap-1"
                @click.stop
              >
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-pencil"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.EDIT')"
                  @click.stop="handleEditScheduledMessage(message)"
                />
                <Button
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.CANCEL')"
                  @click.stop="handleCancelScheduledMessage(message)"
                />
              </div>
            </div>
          </button>
        </div>
      </div>

      <template #footer>
        <div class="flex items-center justify-end w-full gap-3">
          <Button
            :label="t('DIALOG.BUTTONS.CANCEL')"
            variant="link"
            class="h-10 hover:!no-underline hover:text-n-brand"
            @click="showDayDialog = false"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>

<style scoped>
.calendar-view-container {
  background: var(--n-background);
}

.calendar-day {
  position: relative;
  box-sizing: border-box;
}

.calendar-day.selected-day {
  border-top: 2px solid rgb(5 150 105) !important;
  border-right: 2px solid rgb(5 150 105) !important;
  border-bottom: 2px solid rgb(5 150 105) !important;
  border-left: 2px solid rgb(5 150 105) !important;
  z-index: 10;
}
</style>
