<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  refreshToken: {
    type: Number,
    default: 0,
  },
  initialConversationId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['close', 'edit-scheduled-message', 'cancelled']);

const store = useStore();
const { t } = useI18n();

const showCancelled = ref(false);
const searchQuery = ref('');
const selectedConversationId = ref(null);
const messageToCancel = ref(null);
const cancelDialogRef = ref(null);

const scheduledMessages = computed(() => store.getters['kanban/getScheduledMessages']);
const isLoading = computed(() => {
  const uiFlags = store.getters['kanban/getUIFlags'];
  return uiFlags.isFetching || uiFlags.isDeleting;
});

const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const getConversationFromStore = conversationId => {
  if (!conversationId || !getConversationById.value) return null;
  return getConversationById.value(Number(conversationId));
};

const getContactForMessage = message => {
  const conversation = getConversationFromStore(message.conversationId);
  const contact = conversation?.meta?.sender || conversation?.contact;

  return {
    name:
      contact?.name ||
      `${t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION')} #${
        message.conversationDisplayId || message.conversationId
      }`,
    phone: contact?.phone_number || contact?.phoneNumber || '',
    avatar: contact?.thumbnail || contact?.avatar_url || contact?.avatar || '',
  };
};

const statusLabel = status => {
  const map = {
    pending: t('KANBAN.SCHEDULED_MESSAGES.STATUS.PENDING'),
    sent: t('KANBAN.SCHEDULED_MESSAGES.STATUS.SENT'),
    failed: t('KANBAN.SCHEDULED_MESSAGES.STATUS.FAILED'),
    cancelled: t('KANBAN.SCHEDULED_MESSAGES.STATUS.CANCELLED'),
  };
  return map[status] || status;
};

const statusBadgeClass = status => {
  if (status === 'pending') return 'bg-n-teal-4 text-n-teal-11';
  if (status === 'cancelled') return 'bg-n-slate-4 text-n-slate-11';
  if (status === 'failed') return 'bg-n-ruby-4 text-n-ruby-11';
  if (status === 'sent') return 'bg-n-emerald-4 text-n-emerald-11';
  return 'bg-n-slate-4 text-n-slate-11';
};

const filteredMessages = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();

  return scheduledMessages.value.filter(message => {
    if (!showCancelled.value && message.status === 'cancelled') {
      return false;
    }

    if (
      selectedConversationId.value &&
      Number(message.conversationId) !== Number(selectedConversationId.value)
    ) {
      return false;
    }

    if (!query) return true;

    const contact = getContactForMessage(message);
    const haystack = [
      message.message || '',
      contact.name || '',
      contact.phone || '',
      String(message.conversationDisplayId || message.conversationId || ''),
    ]
      .join(' ')
      .toLowerCase();

    return haystack.includes(query);
  });
});

const pendingCount = computed(() =>
  scheduledMessages.value.filter(message => message.status === 'pending').length
);

const fetchMessages = async () => {
  if (!props.show) return;

  const payload = {
    status: showCancelled.value ? 'all' : 'pending',
  };

  await store.dispatch('kanban/fetchScheduledMessages', payload);
};

const handleEdit = message => {
  emit('edit-scheduled-message', message);
};

const askCancel = message => {
  messageToCancel.value = message;
};

const closeCancelDialog = () => {
  messageToCancel.value = null;
};

const confirmCancel = async () => {
  if (!messageToCancel.value?.id) return;

  try {
    await store.dispatch('kanban/deleteScheduledMessage', messageToCancel.value.id);
    await fetchMessages();
    emit('cancelled', messageToCancel.value.id);
    closeCancelDialog();
  } catch (error) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CANCEL_ERROR'));
  }
};

watch(
  () => props.show,
  async isVisible => {
    if (!isVisible) return;
    await fetchMessages();
  }
);

watch(
  () => props.initialConversationId,
  conversationId => {
    selectedConversationId.value = conversationId ? Number(conversationId) : null;
  },
  { immediate: true }
);

watch(showCancelled, async () => {
  await fetchMessages();
});

watch(messageToCancel, async value => {
  if (!value) return;
  await nextTick();
  cancelDialogRef.value?.open?.();
});

watch(
  () => props.refreshToken,
  async () => {
    if (!props.show) return;
    await fetchMessages();
  }
);

const clearConversationFilter = () => {
  selectedConversationId.value = null;
};
</script>

<template>
  <div v-if="show" class="fixed inset-0 z-50 flex justify-end">
    <button
      type="button"
      class="absolute inset-0 bg-n-alpha-black1 backdrop-blur-[2px]"
      @click="emit('close')"
    />

    <div
      class="relative h-full w-full max-w-[28rem] bg-n-solid-2 border-l border-n-weak shadow-2xl flex flex-col"
    >
      <div class="px-5 py-4 border-b border-n-weak bg-n-solid-3">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('KANBAN.SCHEDULED_MESSAGES.DRAWER_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-10 mt-1">
              {{ t('KANBAN.SCHEDULED_MESSAGES.PENDING_COUNT', { count: pendingCount }) }}
            </p>
          </div>
          <Button
            variant="ghost"
            icon="i-lucide-x"
            class="!h-8 !w-8 !p-0"
            @click="emit('close')"
          />
        </div>

        <div class="mt-4 space-y-3">
          <div class="relative">
            <Icon
              icon="i-lucide-search"
              class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="t('KANBAN.SCHEDULED_MESSAGES.SEARCH_PLACEHOLDER')"
              class="w-full pl-9 pr-3 py-2.5 rounded-lg border border-n-weak bg-n-solid-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
            />
          </div>

          <div class="flex items-center justify-between gap-3">
            <Button
              :icon="showCancelled ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              size="sm"
              variant="ghost"
              @click="showCancelled = !showCancelled"
            >
              <span class="ml-2">
                {{
                  showCancelled
                    ? t('KANBAN.SCHEDULED_MESSAGES.HIDE_CANCELLED')
                    : t('KANBAN.SCHEDULED_MESSAGES.SHOW_CANCELLED')
                }}
              </span>
            </Button>

            <Button
              v-if="selectedConversationId"
              icon="i-lucide-filter-x"
              size="sm"
              variant="ghost"
              @click="clearConversationFilter"
            >
              <span class="ml-2">{{ t('KANBAN.SCHEDULED_MESSAGES.CLEAR_FILTER') }}</span>
            </Button>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <div
          v-if="isLoading"
          class="h-full flex items-center justify-center text-sm text-n-slate-10"
        >
          <Icon icon="i-lucide-loader-2" class="size-5 animate-spin mr-2" />
          {{ t('KANBAN.LOADING') }}
        </div>

        <div
          v-else-if="filteredMessages.length === 0"
          class="h-full flex flex-col items-center justify-center text-center px-6"
        >
          <Icon icon="i-lucide-calendar-x2" class="size-10 text-n-slate-9 mb-3" />
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.SCHEDULED_MESSAGES.NO_RESULTS') }}
          </p>
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="message in filteredMessages"
            :key="message.id"
            class="rounded-xl border border-n-weak bg-n-solid-3 p-3"
          >
            <div class="flex items-center justify-between gap-2 mb-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{ format(new Date(message.scheduledAt), 'dd/MM/yyyy HH:mm', { locale: ptBR }) }}
              </span>
              <span
                class="px-2 py-0.5 rounded-full text-[11px] font-semibold"
                :class="statusBadgeClass(message.status)"
              >
                {{ statusLabel(message.status) }}
              </span>
            </div>

            <div class="flex items-start gap-2.5">
              <Avatar
                :src="getContactForMessage(message).avatar"
                :name="getContactForMessage(message).name"
                :size="32"
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-semibold text-n-slate-12 truncate">
                  {{ getContactForMessage(message).name }}
                </p>
                <p
                  v-if="getContactForMessage(message).phone"
                  class="text-xs text-n-slate-10 font-mono truncate mt-0.5"
                >
                  {{ getContactForMessage(message).phone }}
                </p>
                <p class="text-xs text-n-slate-11 mt-1 line-clamp-2">
                  {{ message.message || t('KANBAN.SCHEDULED_MESSAGES.NO_TEXT') }}
                </p>
              </div>
            </div>

            <div class="mt-3 flex items-center justify-end gap-2">
              <template v-if="message.status === 'pending'">
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-pencil"
                  @click="handleEdit(message)"
                >
                  <span class="ml-1">{{ t('KANBAN.SCHEDULED_MESSAGES.EDIT') }}</span>
                </Button>
                <Button
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  @click="askCancel(message)"
                >
                  <span class="ml-1">{{ t('KANBAN.SCHEDULED_MESSAGES.CANCEL') }}</span>
                </Button>
              </template>
              <span v-else class="text-xs text-n-slate-10">
                {{ t('KANBAN.SCHEDULED_MESSAGES.READONLY') }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      v-if="messageToCancel"
      ref="cancelDialogRef"
      :title="t('KANBAN.SCHEDULED_MESSAGES.CANCEL_CONFIRM_TITLE')"
      :description="t('KANBAN.SCHEDULED_MESSAGES.CANCEL_CONFIRM_MESSAGE')"
      :confirm-button-label="t('KANBAN.SCHEDULED_MESSAGES.CANCEL')"
      type="alert"
      @close="closeCancelDialog"
      @confirm="confirmCancel"
    />
  </div>
</template>
