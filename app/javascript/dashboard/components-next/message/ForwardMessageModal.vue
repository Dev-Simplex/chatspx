<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ConversationsAPI from 'dashboard/api/inbox/conversation';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import { MESSAGE_TYPES } from './constants';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  message: {
    type: Object,
    required: true,
  },
  selectedMessageIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close', 'forwarded']);

const { t } = useI18n();
const store = useStore();

const searchQuery = ref('');
const selectedConversations = ref([]);
const selectedMessageIds = ref([]);
const showMessagePicker = ref(false);
const isForwarding = ref(false);
const isLoadingConversations = ref(false);
const allConversations = ref([]);
const currentConversationId = computed(() => props.message?.conversationId || props.message?.conversation_id);
const MAX_MESSAGES = 20;

// Buscar conversas quando modal abrir
const fetchConversations = async () => {
  if (isLoadingConversations.value) return;
  
  isLoadingConversations.value = true;
  try {
    const response = await ConversationsAPI.getAllConversationsForForward({
      status: 'all',
      page: 1,
      perPage: 100,
    });
    
    // Filtrar a conversa atual e formatar dados
    const conversations = (response.data?.data?.payload || response.data?.payload || []).filter(
      conv => conv.id !== currentConversationId.value
    );
    
    allConversations.value = conversations;
  } catch (error) {
    console.error('Error fetching conversations:', error);
    useAlert(
      t('CONVERSATION.FORWARD.ERROR_LOADING') || 'Erro ao carregar conversas'
    );
    // Fallback para conversas do store
    const storeConversations = store.getters.getAllConversations || [];
    allConversations.value = storeConversations.filter(
      conv => conv.id !== currentConversationId.value
    );
  } finally {
    isLoadingConversations.value = false;
  }
};

const selectedConversationDetails = computed(() => {
  const selectedSet = new Set(selectedConversations.value);
  return allConversations.value.filter(conv => selectedSet.has(conv.id));
});

const getConversationName = conversation =>
  conversation.meta?.sender?.name || t('CONVERSATION.UNKNOWN_CONTACT');

const getConversationSecondary = conversation =>
  conversation.meta?.sender?.phone_number ||
  conversation.meta?.sender?.email ||
  '';

const getConversationAvatar = conversation =>
  conversation.meta?.sender?.thumbnail ||
  conversation.meta?.sender?.avatar_url ||
  '';

const getLastMessagePreview = conversation => {
  const message = conversation.messages?.[0];
  if (!message) return '';
  if (message.content) return message.content;
  const attachmentCount = message.attachments?.length || 0;
  if (attachmentCount > 0) {
    return t('CONVERSATION.FORWARD.ATTACHMENT_PREVIEW', {
      count: attachmentCount,
    });
  }
  return t('CONVERSATION.NO_CONTENT');
};

// Filter conversations based on search
const filteredConversations = computed(() => {
  if (!searchQuery.value) {
    return allConversations.value.slice(0, 50); // Show first 50
  }
  
  const query = searchQuery.value.toLowerCase();
  return allConversations.value.filter(conv => {
    const contactName = conv.meta?.sender?.name?.toLowerCase() || '';
    const email = conv.meta?.sender?.email?.toLowerCase() || '';
    const phone = conv.meta?.sender?.phone_number?.toLowerCase() || '';
    const displayId = String(conv.id || '').toLowerCase();
    return (
      contactName.includes(query) ||
      email.includes(query) ||
      phone.includes(query) ||
      displayId.includes(query)
    );
  });
});

const isConversationSelected = (convId) => {
  return selectedConversations.value.includes(convId);
};

const messageCandidates = computed(() => {
  const selectedChat = store.getters.getSelectedChat || {};
  if (!selectedChat.id) return [];
  if (Number(selectedChat.id) !== Number(currentConversationId.value)) {
    return [];
  }

  const messages = selectedChat.messages || [];
  return messages
    .filter(message => {
      const messageType = message.message_type ?? message.messageType;
      if (messageType === MESSAGE_TYPES.ACTIVITY) return false;
      const contentAttributes =
        message.content_attributes ?? message.contentAttributes ?? {};
      if (contentAttributes.deleted) return false;
      const hasContent = !!message.content;
      const hasAttachments = (message.attachments?.length || 0) > 0;
      return hasContent || hasAttachments;
    })
    .slice()
    .reverse();
});

const getMessageTimestamp = message => {
  const timestamp = message?.created_at ?? message?.createdAt ?? 0;
  return Number(timestamp) || 0;
};

const selectedMessages = computed(() => {
  const selectedSet = new Set(selectedMessageIds.value);
  return messageCandidates.value.filter(message => selectedSet.has(message.id));
});

const orderedSelectedMessages = computed(() => {
  return selectedMessages.value
    .slice()
    .sort((a, b) => {
      const timeDiff = getMessageTimestamp(a) - getMessageTimestamp(b);
      if (timeDiff !== 0) return timeDiff;
      return a.id - b.id;
    });
});

const getMessagePreview = message => {
  if (message?.content) return message.content;
  const attachmentCount = message?.attachments?.length || 0;
  if (attachmentCount > 0) {
    return t('CONVERSATION.FORWARD.ATTACHMENT_PREVIEW', {
      count: attachmentCount,
    });
  }
  return t('CONVERSATION.NO_CONTENT');
};

const selectedMessagePreviewList = computed(() => {
  if (selectedMessageIds.value.length === 0) return [];
  if (orderedSelectedMessages.value.length) {
    return orderedSelectedMessages.value.map(getMessagePreview);
  }
  if (props.message && selectedMessageIds.value.includes(props.message.id)) {
    return [getMessagePreview(props.message)];
  }
  return [];
});

const messagePreviewLabel = computed(() =>
  selectedMessageIds.value.length > 1
    ? t('CONVERSATION.FORWARD.MESSAGES_PREVIEW')
    : t('CONVERSATION.FORWARD.MESSAGE_PREVIEW')
);

const isMessageSelected = messageId => {
  return selectedMessageIds.value.includes(messageId);
};

const toggleMessageSelection = messageId => {
  const index = selectedMessageIds.value.indexOf(messageId);
  if (index > -1) {
    selectedMessageIds.value.splice(index, 1);
    return;
  }
  if (selectedMessageIds.value.length >= MAX_MESSAGES) {
    useAlert(
      t('CONVERSATION.FORWARD.MAX_MESSAGES', { count: MAX_MESSAGES })
    );
    return;
  }
  selectedMessageIds.value.push(messageId);
};

const toggleConversation = (convId) => {
  const index = selectedConversations.value.indexOf(convId);
  if (index > -1) {
    selectedConversations.value.splice(index, 1);
  } else {
    if (selectedConversations.value.length >= 10) {
      useAlert(t('CONVERSATION.FORWARD.MAX_CONVERSATIONS'));
      return;
    }
    selectedConversations.value.push(convId);
  }
};

const handleForward = async () => {
  if (selectedConversations.value.length === 0) {
    useAlert(t('CONVERSATION.FORWARD.SELECT_CONVERSATIONS'));
    return;
  }

  if (selectedMessageIds.value.length === 0) {
    useAlert(t('CONVERSATION.FORWARD.SELECT_MESSAGES'));
    return;
  }
  
  isForwarding.value = true;
  
  try {
    const accountId = store.getters.getCurrentAccountId;
    // Usar display_id se disponível, senão usar id
    const conversationIds = selectedConversations.value.map(id => {
      const conv = allConversations.value.find(c => c.id === id);
      return conv?.display_id || conv?.id || id;
    });
    
    const selectedSet = new Set(selectedMessageIds.value);
    const orderedMessages = messageCandidates.value
      .filter(message => selectedSet.has(message.id))
      .slice()
      .sort((a, b) => {
        const timeDiff = getMessageTimestamp(a) - getMessageTimestamp(b);
        if (timeDiff !== 0) return timeDiff;
        return a.id - b.id;
      });

    const orderedMessageIds = orderedMessages.map(message => message.id);
    const fallbackIds = selectedMessageIds.value.filter(
      messageId => !orderedMessageIds.includes(messageId)
    );
    const messageIds = [...new Set([...orderedMessageIds, ...fallbackIds])];

    let successCount = 0;
    for (const messageId of messageIds) {
      await ConversationsAPI.forwardMessage({
        accountId,
        messageId,
        conversationIds,
      });
      successCount += 1;
    }

    if (successCount === 0) throw new Error('No messages forwarded');

    useAlert(
      t(
        messageIds.length > 1
          ? 'CONVERSATION.FORWARD.SUCCESS_MULTIPLE'
          : 'CONVERSATION.FORWARD.SUCCESS',
        {
          count: selectedConversations.value.length,
          messages: messageIds.length,
        }
      )
    );
    
    emit('forwarded', {
      forwarded_count: selectedConversations.value.length,
      conversation_count: selectedConversations.value.length,
      message_count: messageIds.length,
    });
    handleClose();
  } catch (error) {
    console.error('Error forwarding message:', error);
    useAlert(t('CONVERSATION.FORWARD.ERROR') || 'Erro ao encaminhar mensagem');
  } finally {
    isForwarding.value = false;
  }
};

const handleClose = () => {
  searchQuery.value = '';
  selectedConversations.value = [];
  selectedMessageIds.value = [];
  showMessagePicker.value = false;
  emit('close');
};

// Reset state when modal closes and fetch conversations when opens
watch(() => props.show, (newValue) => {
  if (newValue) {
    fetchConversations();
    if (props.selectedMessageIds?.length) {
      selectedMessageIds.value = [...props.selectedMessageIds];
    } else {
      selectedMessageIds.value = props.message?.id ? [props.message.id] : [];
    }
    showMessagePicker.value = false;
  } else {
    searchQuery.value = '';
    selectedConversations.value = [];
    selectedMessageIds.value = [];
    showMessagePicker.value = false;
  }
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition ease-out duration-200"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition ease-in duration-150"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        class="fixed inset-0 z-[10000] overflow-y-auto"
        @click.self="handleClose"
      >
        <!-- Overlay -->
        <div class="fixed inset-0 bg-slate-900/60 dark:bg-black/70" />
        
        <!-- Modal -->
        <div class="relative flex min-h-full items-center justify-center p-4">
          <div
            class="relative w-full max-w-3xl bg-white dark:bg-slate-800 rounded-2xl shadow-2xl ring-1 ring-slate-900/5"
          >
            <!-- Header -->
            <div class="flex items-center justify-between px-6 py-5 border-b border-slate-200 dark:border-slate-700">
              <div class="flex items-center gap-3">
                <span class="flex items-center justify-center size-10 rounded-full bg-woot-50 text-woot-600 dark:bg-woot-900/40 dark:text-woot-200">
                  <Icon icon="i-lucide-share-2" class="size-5" />
                </span>
                <div>
                  <h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
                    {{ t('CONVERSATION.FORWARD.TITLE') }}
                  </h3>
                  <p class="text-xs text-slate-500 dark:text-slate-400">
                    {{ t('CONVERSATION.FORWARD.SELECTED_COUNT', { count: selectedConversations.length }) }}
                  </p>
                </div>
              </div>
              <button
                class="p-2 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
                @click="handleClose"
              >
                <Icon icon="i-lucide-x" class="size-5 text-slate-600 dark:text-slate-300" />
              </button>
            </div>
            
            <!-- Message Preview -->
            <div class="px-6 py-4 bg-slate-50 dark:bg-slate-900/50 border-b border-slate-200 dark:border-slate-700">
              <p class="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400 mb-2">
                {{ messagePreviewLabel }}
              </p>
              <div class="space-y-2">
                <p
                  v-if="selectedMessagePreviewList.length === 0"
                  class="text-sm text-slate-500 dark:text-slate-400"
                >
                  {{ t('CONVERSATION.FORWARD.SELECT_MESSAGES') }}
                </p>
                <div
                  v-for="(preview, index) in selectedMessagePreviewList.slice(0, 3)"
                  :key="`preview-${index}`"
                  class="p-3 bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700"
                >
                  <p class="text-sm text-slate-900 dark:text-slate-100 line-clamp-2">
                    {{ preview }}
                  </p>
                </div>
                <p
                  v-if="selectedMessagePreviewList.length > 3"
                  class="text-xs text-slate-500 dark:text-slate-400"
                >
                  {{ t('CONVERSATION.FORWARD.MORE_MESSAGES', { count: selectedMessagePreviewList.length - 3 }) }}
                </p>
              </div>
            </div>

            <!-- Message Picker -->
            <div class="px-6 py-3 border-b border-slate-200 dark:border-slate-700">
              <button
                class="inline-flex items-center gap-2 text-sm font-medium text-woot-600 dark:text-woot-200 hover:text-woot-700"
                @click="showMessagePicker = !showMessagePicker"
              >
                <Icon icon="i-lucide-layers" class="size-4" />
                {{ t('CONVERSATION.FORWARD.SELECT_MORE_MESSAGES') }}
              </button>
            </div>

            <div
              v-if="showMessagePicker"
              class="px-6 py-3 border-b border-slate-200 dark:border-slate-700"
            >
              <div class="max-h-60 overflow-y-auto space-y-2">
                <div
                  v-if="messageCandidates.length === 0"
                  class="text-sm text-slate-500 dark:text-slate-400 py-2"
                >
                  {{ t('CONVERSATION.FORWARD.NO_MESSAGES') }}
                </div>
                <div
                  v-for="message in messageCandidates"
                  :key="`message-${message.id}`"
                  class="flex items-start gap-3 px-3 py-2 rounded-xl cursor-pointer transition-colors border border-transparent hover:bg-slate-50 dark:hover:bg-slate-900/40"
                  :class="{
                    'bg-woot-50/80 border-woot-200 dark:bg-woot-900/30 dark:border-woot-900/80': isMessageSelected(message.id),
                  }"
                  @click="toggleMessageSelection(message.id)"
                >
                  <input
                    type="checkbox"
                    class="mt-1 size-4 text-woot-500 rounded border-slate-300 focus:ring-woot-500"
                    :checked="isMessageSelected(message.id)"
                  />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-slate-900 dark:text-slate-100 line-clamp-2">
                      {{ getMessagePreview(message) }}
                    </p>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Search -->
            <div class="px-6 py-4 border-b border-slate-200 dark:border-slate-700">
              <div class="relative">
                <span
                  class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 size-4 text-slate-400 pointer-events-none inline-block"
                  aria-hidden="true"
                ></span>
                <input
                  v-model="searchQuery"
                  type="text"
                  :placeholder="t('CONVERSATION.FORWARD.SEARCH_CONVERSATIONS')"
                  class="w-full !pl-12 pr-4 py-2.5 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 placeholder-slate-400 focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                />
              </div>
            </div>

            <!-- Selected Conversations -->
            <div
              v-if="selectedConversationDetails.length > 0"
              class="px-6 py-3 border-b border-slate-200 dark:border-slate-700"
            >
              <div class="flex items-center gap-2 overflow-x-auto">
                <div
                  v-for="conversation in selectedConversationDetails"
                  :key="`selected-${conversation.id}`"
                  class="flex items-center gap-2 px-2.5 py-1.5 rounded-full bg-woot-50 text-woot-700 dark:bg-woot-900/30 dark:text-woot-200"
                >
                  <Avatar
                    :name="getConversationName(conversation)"
                    :src="getConversationAvatar(conversation)"
                    :size="20"
                  />
                  <span class="text-xs font-medium truncate max-w-[120px]">
                    {{ getConversationName(conversation) }}
                  </span>
                </div>
              </div>
            </div>
            
            <!-- Conversations List -->
            <div class="max-h-[26rem] overflow-y-auto px-4 py-2">
              <div
                v-if="isLoadingConversations"
                class="text-center py-8 text-slate-500"
              >
                {{ t('CONVERSATION.FORWARD.LOADING') || 'Carregando conversas...' }}
              </div>
              <div
                v-else-if="filteredConversations.length === 0"
                class="text-center py-8 text-slate-500"
              >
                {{ t('CONVERSATION.FORWARD.NO_CONVERSATIONS') || 'Nenhuma conversa encontrada' }}
              </div>
              
              <div
                v-for="conversation in filteredConversations"
                :key="conversation.id"
                class="group flex items-center gap-3 px-3 py-3 rounded-2xl cursor-pointer transition-all border border-transparent hover:border-woot-100 hover:bg-woot-50/60 dark:hover:border-woot-900/60 dark:hover:bg-slate-900/50"
                :class="{
                  'bg-woot-50/80 border-woot-200 dark:bg-woot-900/30 dark:border-woot-900/80': isConversationSelected(conversation.id),
                }"
                @click="toggleConversation(conversation.id)"
              >
                <div class="relative">
                  <Avatar
                    :name="getConversationName(conversation)"
                    :src="getConversationAvatar(conversation)"
                    :size="44"
                  />
                  <span
                    v-if="isConversationSelected(conversation.id)"
                    class="absolute -bottom-1 -right-1 flex items-center justify-center size-5 rounded-full bg-woot-500 text-white shadow"
                  >
                    <Icon icon="i-lucide-check" class="size-3" />
                  </span>
                </div>
                
                <div class="flex-1 min-w-0">
                  <div class="flex items-center justify-between gap-2">
                    <p class="text-sm font-semibold text-slate-900 dark:text-slate-100 truncate">
                      {{ getConversationName(conversation) }}
                    </p>
                  </div>
                  <p class="text-xs text-slate-500 dark:text-slate-400 truncate">
                    {{ getConversationSecondary(conversation) }}
                  </p>
                  <p class="text-xs text-slate-400 dark:text-slate-500 line-clamp-1">
                    {{ getLastMessagePreview(conversation) }}
                  </p>
                </div>
              </div>
            </div>
            
            <!-- Footer -->
            <div class="flex items-center justify-between px-6 py-4 border-t border-slate-200 dark:border-slate-700">
              <p class="text-xs text-slate-500 dark:text-slate-400">
                {{ t('CONVERSATION.FORWARD.MAX_CONVERSATIONS') }}
              </p>
              
              <div class="flex gap-3">
                <button
                  class="px-4 py-2 text-sm font-medium text-slate-700 dark:text-slate-300 bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-xl hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
                  @click="handleClose"
                >
                  {{ t('CONVERSATION.FORWARD.CANCEL') }}
                </button>
                
                <button
                  :disabled="selectedConversations.length === 0 || isForwarding"
                  class="px-5 py-2 text-sm font-medium text-white bg-woot-500 rounded-xl hover:bg-woot-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                  @click="handleForward"
                >
                  {{ isForwarding ? t('CONVERSATION.FORWARD.FORWARDING') : t('CONVERSATION.FORWARD.FORWARD') }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
