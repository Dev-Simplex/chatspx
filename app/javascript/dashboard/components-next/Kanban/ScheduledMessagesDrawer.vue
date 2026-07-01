<script setup>
import { computed, onBeforeUnmount, ref, watch, nextTick } from 'vue';
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

const emit = defineEmits(['close', 'editScheduledMessage', 'cancelled']);

const store = useStore();
const { t } = useI18n();

const statusFilter = ref('all');
const searchQuery = ref('');
const selectedConversationId = ref(null);
const messageToCancel = ref(null);
const cancelDialogRef = ref(null);
let pollingTimer = null;

const scheduledMessages = computed(
  () => store.getters['kanban/getScheduledMessages']
);
const scheduledMeta = computed(() => store.getters['kanban/getScheduledMeta']);
const scheduledFilters = computed(
  () => store.getters['kanban/getScheduledFilters']
);
const isLoading = computed(() => {
  const uiFlags = store.getters['kanban/getUIFlags'];
  return uiFlags.isFetchingScheduledMessages || uiFlags.isDeleting;
});

const getConversationById = computed(
  () => store.getters['conversations/getConversationById']
);

const STATUS_OPTIONS = [
  { key: 'all', label: 'KANBAN.SCHEDULED_MESSAGES.STATUS_FILTER.ALL' },
  { key: 'pending', label: 'KANBAN.SCHEDULED_MESSAGES.STATUS_FILTER.PENDING' },
  { key: 'sent', label: 'KANBAN.SCHEDULED_MESSAGES.STATUS_FILTER.SENT' },
  { key: 'failed', label: 'KANBAN.SCHEDULED_MESSAGES.STATUS_FILTER.FAILED' },
  {
    key: 'cancelled',
    label: 'KANBAN.SCHEDULED_MESSAGES.STATUS_FILTER.CANCELLED',
  },
];

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
      String(message.errorMessage || ''),
    ]
      .join(' ')
      .toLowerCase();

    return haystack.includes(query);
  });
});

const pendingCount = computed(
  () =>
    scheduledMessages.value.filter(message => message.status === 'pending')
      .length
);

const fetchMessages = async ({ append = false } = {}) => {
  if (!props.show) return;

  const payload = {
    status: statusFilter.value,
    conversationId: selectedConversationId.value,
    from: scheduledFilters.value.from,
    to: scheduledFilters.value.to,
    limit: scheduledMeta.value.limit || 50,
    append,
  };

  await store.dispatch('kanban/fetchScheduledMessagesPage', payload);
};

const bootstrapMessages = async () => {
  await store.dispatch('kanban/bootstrapScheduledTimeline', {
    status: statusFilter.value,
    conversationId: selectedConversationId.value,
    from: scheduledFilters.value.from,
    to: scheduledFilters.value.to,
    limit: scheduledMeta.value.limit || 50,
  });
};

const loadMore = async () => {
  if (!scheduledMeta.value.hasMore || isLoading.value) return;

  await store.dispatch('kanban/loadMoreScheduledMessages', {
    status: statusFilter.value,
    conversationId: selectedConversationId.value,
  });
};

const stopPolling = () => {
  if (!pollingTimer) return;
  clearInterval(pollingTimer);
  pollingTimer = null;
};

const startPolling = () => {
  stopPolling();
  pollingTimer = setInterval(() => {
    store.dispatch('kanban/refreshPendingStatuses', {
      status: statusFilter.value,
      conversationId: selectedConversationId.value,
    });
  }, 30_000);
};

const handleEdit = message => {
  emit('editScheduledMessage', message);
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
    await store.dispatch(
      'kanban/deleteScheduledMessage',
      messageToCancel.value.id
    );
    await bootstrapMessages();
    emit('cancelled', messageToCancel.value.id);
    closeCancelDialog();
  } catch (_) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CANCEL_ERROR'));
  }
};

const clearConversationFilter = () => {
  selectedConversationId.value = null;
};

watch(
  () => props.show,
  async isVisible => {
    if (!isVisible) {
      stopPolling();
      return;
    }

    await bootstrapMessages();
    startPolling();
  }
);

watch(
  () => props.initialConversationId,
  conversationId => {
    selectedConversationId.value = conversationId
      ? Number(conversationId)
      : null;
  },
  { immediate: true }
);

watch([statusFilter, selectedConversationId], async () => {
  if (!props.show) return;
  await bootstrapMessages();
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
    await fetchMessages({ append: false });
  }
);

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div v-if="show" class="fixed inset-0 z-50 flex justify-end">
    <button
      type="button"
      class="absolute inset-0 bg-n-alpha-black1 backdrop-blur-[2px]"
      @click="emit('close')"
    />

    <div
      class="relative flex h-full w-full max-w-[30rem] flex-col border-l border-n-weak bg-n-solid-1 shadow-2xl"
    >
      <div
        class="border-b border-n-weak bg-n-slate-2/50 dark:bg-n-solid-3 px-5 py-4"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('KANBAN.SCHEDULED_MESSAGES.DRAWER_TITLE') }}
            </h2>
            <p class="mt-1 text-xs text-n-slate-10">
              {{
                t('KANBAN.SCHEDULED_MESSAGES.PENDING_COUNT', {
                  count: pendingCount,
                })
              }}
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
              class="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-n-slate-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="t('KANBAN.SCHEDULED_MESSAGES.SEARCH_PLACEHOLDER')"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 py-2.5 !pl-10 pr-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            />
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              v-for="option in STATUS_OPTIONS"
              :key="option.key"
              type="button"
              class="rounded-full px-3 py-1 text-xs font-semibold transition"
              :class="
                statusFilter === option.key
                  ? 'bg-n-teal-9 text-n-teal-12 dark:text-white'
                  : 'bg-n-slate-3/50 text-n-slate-11 hover:bg-n-slate-3'
              "
              @click="statusFilter = option.key"
            >
              {{ t(option.label) }}
            </button>
          </div>

          <div
            v-if="selectedConversationId"
            class="flex items-center justify-end gap-2"
          >
            <Button
              icon="i-lucide-filter-x"
              size="sm"
              variant="ghost"
              @click="clearConversationFilter"
            >
              <span class="ml-2">{{
                t('KANBAN.SCHEDULED_MESSAGES.CLEAR_FILTER')
              }}</span>
            </Button>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <div
          v-if="isLoading && scheduledMessages.length === 0"
          class="flex h-full items-center justify-center text-sm text-n-slate-10"
        >
          <Icon icon="i-lucide-loader-2" class="mr-2 size-5 animate-spin" />
          {{ t('KANBAN.LOADING') }}
        </div>

        <div
          v-else-if="filteredMessages.length === 0"
          class="flex h-full flex-col items-center justify-center px-6 text-center"
        >
          <Icon
            icon="i-lucide-calendar-x2"
            class="mb-3 size-10 text-n-slate-9"
          />
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.SCHEDULED_MESSAGES.NO_RESULTS') }}
          </p>
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="message in filteredMessages"
            :key="message.id"
            class="rounded-xl border border-n-weak bg-n-solid-1 p-3 hover:shadow-sm transition-shadow"
          >
            <div class="mb-2 flex items-center justify-between gap-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{
                  format(new Date(message.scheduledAt), 'dd/MM/yyyy HH:mm', {
                    locale: ptBR,
                  })
                }}
              </span>
              <span
                class="rounded-full px-2 py-0.5 text-[11px] font-semibold"
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
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold text-n-slate-12">
                  {{ getContactForMessage(message).name }}
                </p>
                <p
                  v-if="getContactForMessage(message).phone"
                  class="mt-0.5 truncate font-mono text-xs text-n-slate-10"
                >
                  {{ getContactForMessage(message).phone }}
                </p>
                <p class="mt-1 line-clamp-2 text-xs text-n-slate-11">
                  {{
                    message.message || t('KANBAN.SCHEDULED_MESSAGES.NO_TEXT')
                  }}
                </p>
                <p
                  v-if="message.sentAt"
                  class="mt-1 text-[11px] text-n-slate-10"
                >
                  {{ t('KANBAN.SCHEDULED_MESSAGES.SENT_AT') }}:
                  {{
                    format(new Date(message.sentAt), 'dd/MM/yyyy HH:mm', {
                      locale: ptBR,
                    })
                  }}
                </p>
                <p
                  v-if="message.errorMessage"
                  class="mt-1 text-[11px] text-n-ruby-11"
                >
                  {{ message.errorMessage }}
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
                  <span class="ml-1">{{
                    t('KANBAN.SCHEDULED_MESSAGES.EDIT')
                  }}</span>
                </Button>
                <Button
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  @click="askCancel(message)"
                >
                  <span class="ml-1">{{
                    t('KANBAN.SCHEDULED_MESSAGES.CANCEL')
                  }}</span>
                </Button>
              </template>
              <span v-else class="text-xs text-n-slate-10">
                {{ t('KANBAN.SCHEDULED_MESSAGES.READONLY') }}
              </span>
            </div>
          </div>

          <Button
            v-if="scheduledMeta.hasMore"
            variant="ghost"
            class="w-full"
            :is-loading="isLoading"
            @click="loadMore"
          >
            {{ t('COMMON.LOAD_MORE') || 'Carregar mais' }}
          </Button>
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
