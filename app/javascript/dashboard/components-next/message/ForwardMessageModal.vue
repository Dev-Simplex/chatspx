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
  show: { type: Boolean, default: false },
  message: { type: Object, required: true },
  selectedMessageIds: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'forwarded']);

const { t } = useI18n();
const store = useStore();

const searchQuery = ref('');
const selectedItems = ref([]);
const pickedMessageIds = ref([]);
const showMessagePicker = ref(false);
const isForwarding = ref(false);
const isLoadingConversations = ref(false);
const isSearching = ref(false);
const allConversations = ref([]);
const searchResults = ref([]);
const searchTimeout = ref(null);
const currentConversationId = computed(
  () => props.message?.conversationId || props.message?.conversation_id
);
const MAX_MESSAGES = 20;
const MAX_TARGETS = 10;

const handleClose = () => {
  searchQuery.value = '';
  selectedItems.value = [];
  pickedMessageIds.value = [];
  showMessagePicker.value = false;
  searchResults.value = [];
  emit('close');
};

const mapConversation = (conv, fallbackName) => ({
  id: conv.id,
  displayId: conv.display_id || conv.id,
  type: 'conversation',
  name: conv.meta?.sender?.name || fallbackName,
  phone: conv.meta?.sender?.phone_number || '',
  email: conv.meta?.sender?.email || '',
  avatar: conv.meta?.sender?.thumbnail || conv.meta?.sender?.avatar_url || '',
  lastMessage: conv.messages?.[0]?.content || '',
  contactId: conv.meta?.sender?.id,
});

const fetchConversations = async () => {
  if (isLoadingConversations.value) return;
  isLoadingConversations.value = true;
  try {
    const response = await ConversationsAPI.getAllConversationsForForward({
      status: 'all',
      page: 1,
      perPage: 100,
    });
    const conversations = (
      response.data?.data?.payload ||
      response.data?.payload ||
      []
    ).filter(conv => conv.id !== currentConversationId.value);
    const unknownLabel = t('CONVERSATION.UNKNOWN_CONTACT');
    allConversations.value = conversations.map(conv =>
      mapConversation(conv, unknownLabel)
    );
  } catch {
    const storeConversations = store.getters.getAllConversations || [];
    const unknownLabel = t('CONVERSATION.UNKNOWN_CONTACT');
    allConversations.value = storeConversations
      .filter(conv => conv.id !== currentConversationId.value)
      .map(conv => mapConversation(conv, unknownLabel));
  } finally {
    isLoadingConversations.value = false;
  }
};

const searchContacts = async query => {
  if (!query || query.length < 2) {
    searchResults.value = [];
    return;
  }
  isSearching.value = true;
  try {
    const response = await ConversationsAPI.searchContactsForForward({
      query,
    });
    const contacts = response.data?.payload || [];
    const existingContactIds = new Set(
      allConversations.value.map(c => c.contactId).filter(Boolean)
    );
    const unknownLabel = t('CONVERSATION.UNKNOWN_CONTACT');
    searchResults.value = contacts
      .filter(contact => !existingContactIds.has(contact.id))
      .map(contact => ({
        id: `contact-${contact.id}`,
        contactId: contact.id,
        type: 'contact',
        name: contact.name || unknownLabel,
        phone: contact.phoneNumber || '',
        email: contact.email || '',
        avatar: contact.thumbnail || '',
        lastMessage: '',
      }));
  } catch {
    searchResults.value = [];
  } finally {
    isSearching.value = false;
  }
};

const debouncedSearch = query => {
  clearTimeout(searchTimeout.value);
  searchTimeout.value = setTimeout(() => searchContacts(query), 300);
};

watch(searchQuery, newQuery => {
  if (newQuery && newQuery.length >= 2) {
    debouncedSearch(newQuery);
  } else {
    searchResults.value = [];
  }
});

const filteredList = computed(() => {
  const query = searchQuery.value?.toLowerCase();
  let conversationItems = allConversations.value;
  if (query && query.length >= 1) {
    conversationItems = conversationItems.filter(
      item =>
        item.name?.toLowerCase().includes(query) ||
        item.email?.toLowerCase().includes(query) ||
        item.phone?.toLowerCase().includes(query) ||
        String(item.displayId).includes(query)
    );
  } else {
    conversationItems = conversationItems.slice(0, 50);
  }
  return [...conversationItems, ...searchResults.value];
});

const selectedItemDetails = computed(() => {
  const selectedSet = new Set(selectedItems.value);
  const fromConversations = allConversations.value.filter(c =>
    selectedSet.has(c.id)
  );
  const fromContacts = searchResults.value.filter(c => selectedSet.has(c.id));
  return [...fromConversations, ...fromContacts];
});

const isItemSelected = itemId => selectedItems.value.includes(itemId);

const toggleItem = itemId => {
  const index = selectedItems.value.indexOf(itemId);
  if (index > -1) {
    selectedItems.value.splice(index, 1);
  } else {
    if (selectedItems.value.length >= MAX_TARGETS) {
      useAlert(t('CONVERSATION.FORWARD.MAX_CONVERSATIONS'));
      return;
    }
    selectedItems.value.push(itemId);
  }
};

const removeSelectedItem = itemId => {
  const index = selectedItems.value.indexOf(itemId);
  if (index > -1) selectedItems.value.splice(index, 1);
};

const messageCandidates = computed(() => {
  const selectedChat = store.getters.getSelectedChat || {};
  if (!selectedChat.id) return [];
  if (Number(selectedChat.id) !== Number(currentConversationId.value))
    return [];
  const messages = selectedChat.messages || [];
  return messages
    .filter(msg => {
      const messageType = msg.message_type ?? msg.messageType;
      if (messageType === MESSAGE_TYPES.ACTIVITY) return false;
      const contentAttributes =
        msg.content_attributes ?? msg.contentAttributes ?? {};
      if (contentAttributes.deleted) return false;
      return !!msg.content || (msg.attachments?.length || 0) > 0;
    })
    .slice()
    .reverse();
});

const getMessageTimestamp = msg => {
  const timestamp = msg?.created_at ?? msg?.createdAt ?? 0;
  return Number(timestamp) || 0;
};

const selectedMessages = computed(() => {
  const selectedSet = new Set(pickedMessageIds.value);
  return messageCandidates.value.filter(msg => selectedSet.has(msg.id));
});

const orderedSelectedMessages = computed(() =>
  selectedMessages.value.slice().sort((a, b) => {
    const timeDiff = getMessageTimestamp(a) - getMessageTimestamp(b);
    if (timeDiff !== 0) return timeDiff;
    return a.id - b.id;
  })
);

const getMessagePreview = msg => {
  if (msg?.content) return msg.content;
  const attachmentCount = msg?.attachments?.length || 0;
  if (attachmentCount > 0) {
    return t('CONVERSATION.FORWARD.ATTACHMENT_PREVIEW', {
      count: attachmentCount,
    });
  }
  return t('CONVERSATION.NO_CONTENT');
};

const selectedMessagePreviewList = computed(() => {
  if (pickedMessageIds.value.length === 0) return [];
  if (orderedSelectedMessages.value.length) {
    return orderedSelectedMessages.value.map(getMessagePreview);
  }
  if (props.message && pickedMessageIds.value.includes(props.message.id)) {
    return [getMessagePreview(props.message)];
  }
  return [];
});

const messagePreviewLabel = computed(() =>
  pickedMessageIds.value.length > 1
    ? t('CONVERSATION.FORWARD.MESSAGES_PREVIEW')
    : t('CONVERSATION.FORWARD.MESSAGE_PREVIEW')
);

const isMessageSelected = messageId =>
  pickedMessageIds.value.includes(messageId);

const toggleMessageSelection = messageId => {
  const index = pickedMessageIds.value.indexOf(messageId);
  if (index > -1) {
    pickedMessageIds.value.splice(index, 1);
    return;
  }
  if (pickedMessageIds.value.length >= MAX_MESSAGES) {
    useAlert(t('CONVERSATION.FORWARD.MAX_MESSAGES', { count: MAX_MESSAGES }));
    return;
  }
  pickedMessageIds.value.push(messageId);
};

const forwardAllMessages = (messageIds, conversationIds, contactIds) =>
  Promise.all(
    messageIds.map(messageId =>
      ConversationsAPI.forwardMessage({
        messageId,
        conversationIds,
        contactIds,
      })
    )
  );

const handleForward = async () => {
  if (selectedItems.value.length === 0) {
    useAlert(t('CONVERSATION.FORWARD.SELECT_CONVERSATIONS'));
    return;
  }
  if (pickedMessageIds.value.length === 0) {
    useAlert(t('CONVERSATION.FORWARD.SELECT_MESSAGES'));
    return;
  }

  isForwarding.value = true;

  try {
    const conversationIds = [];
    const contactIds = [];

    selectedItems.value.forEach(itemId => {
      if (typeof itemId === 'string' && itemId.startsWith('contact-')) {
        contactIds.push(Number(itemId.replace('contact-', '')));
      } else {
        const conv = allConversations.value.find(c => c.id === itemId);
        conversationIds.push(conv?.displayId || itemId);
      }
    });

    const selectedSet = new Set(pickedMessageIds.value);
    const orderedMessages = messageCandidates.value
      .filter(msg => selectedSet.has(msg.id))
      .slice()
      .sort((a, b) => {
        const timeDiff = getMessageTimestamp(a) - getMessageTimestamp(b);
        if (timeDiff !== 0) return timeDiff;
        return a.id - b.id;
      });

    const orderedMessageIds = orderedMessages.map(msg => msg.id);
    const fallbackIds = pickedMessageIds.value.filter(
      id => !orderedMessageIds.includes(id)
    );
    const messageIds = [...new Set([...orderedMessageIds, ...fallbackIds])];

    await forwardAllMessages(messageIds, conversationIds, contactIds);

    const successKey =
      messageIds.length > 1
        ? 'CONVERSATION.FORWARD.SUCCESS_MULTIPLE'
        : 'CONVERSATION.FORWARD.SUCCESS';
    useAlert(
      t(successKey, {
        count: selectedItems.value.length,
        messages: messageIds.length,
      })
    );

    emit('forwarded', {
      forwarded_count: selectedItems.value.length,
      conversation_count: conversationIds.length,
      contact_count: contactIds.length,
      message_count: messageIds.length,
    });
    handleClose();
  } catch {
    useAlert(t('CONVERSATION.FORWARD.ERROR'));
  } finally {
    isForwarding.value = false;
  }
};

watch(
  () => props.show,
  newValue => {
    if (newValue) {
      fetchConversations();
      if (props.selectedMessageIds?.length) {
        pickedMessageIds.value = [...props.selectedMessageIds];
      } else {
        pickedMessageIds.value = props.message?.id ? [props.message.id] : [];
      }
      showMessagePicker.value = false;
    } else {
      handleClose();
    }
  }
);
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
        <div class="fixed inset-0 bg-n-slate-12/60 dark:bg-n-black/70" />

        <div class="relative flex min-h-full items-center justify-center p-4">
          <div
            class="relative flex w-full max-w-md max-h-[85vh] flex-col bg-n-background rounded-2xl shadow-2xl ring-1 ring-n-slate-12/5"
          >
            <!-- Header -->
            <div
              class="flex items-center gap-3 px-4 py-3 border-b border-n-weak"
            >
              <button
                class="p-1.5 rounded-full hover:bg-n-slate-3 transition-colors"
                @click="handleClose"
              >
                <Icon
                  icon="i-lucide-arrow-left"
                  class="size-5 text-n-slate-11"
                />
              </button>
              <div class="flex-1">
                <h3 class="text-base font-semibold text-n-slate-12">
                  {{ t('CONVERSATION.FORWARD.TITLE') }}
                </h3>
                <p
                  v-if="selectedItems.length > 0"
                  class="text-xs text-n-slate-11"
                >
                  {{
                    t('CONVERSATION.FORWARD.SELECTED_COUNT', {
                      count: selectedItems.length,
                    })
                  }}
                </p>
              </div>
            </div>

            <!-- Search -->
            <div class="px-3 py-2 border-b border-n-weak">
              <div class="relative">
                <span
                  class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-10 pointer-events-none inline-block"
                  aria-hidden="true"
                />
                <input
                  v-model="searchQuery"
                  type="text"
                  :placeholder="t('CONVERSATION.FORWARD.SEARCH_PLACEHOLDER')"
                  class="w-full !pl-10 pr-4 py-2 border-0 bg-n-slate-3 rounded-lg text-sm text-n-slate-12 placeholder-n-slate-10 focus:ring-1 focus:ring-n-brand"
                />
              </div>
            </div>

            <!-- Selected chips -->
            <div
              v-if="selectedItemDetails.length > 0"
              class="flex flex-wrap gap-1.5 px-3 py-2 border-b border-n-weak"
            >
              <div
                v-for="item in selectedItemDetails"
                :key="`chip-${item.id}`"
                class="flex items-center gap-1.5 pl-1 pr-2 py-0.5 rounded-full bg-woot-50 dark:bg-woot-900/30"
              >
                <Avatar :name="item.name" :src="item.avatar" :size="20" />
                <span
                  class="text-xs font-medium text-woot-700 dark:text-woot-200 max-w-[80px] truncate"
                >
                  {{ item.name }}
                </span>
                <button
                  class="p-0.5 rounded-full hover:bg-woot-200 dark:hover:bg-woot-800 transition-colors"
                  @click.stop="removeSelectedItem(item.id)"
                >
                  <Icon icon="i-lucide-x" class="size-3 text-n-brand" />
                </button>
              </div>
            </div>

            <!-- Conversations & Contacts List -->
            <div class="flex-1 overflow-y-auto min-h-0">
              <div
                v-if="isLoadingConversations"
                class="flex items-center justify-center py-12 text-n-slate-10"
              >
                <Icon
                  icon="i-lucide-loader-2"
                  class="size-5 animate-spin mr-2"
                />
                {{ t('CONVERSATION.FORWARD.LOADING') }}
              </div>

              <div
                v-else-if="filteredList.length === 0 && !isSearching"
                class="text-center py-12 text-n-slate-10 text-sm"
              >
                {{ t('CONVERSATION.FORWARD.NO_RESULTS') }}
              </div>

              <template v-else>
                <div
                  v-if="searchResults.length > 0 && searchQuery.length >= 2"
                  class="px-4 pt-3 pb-1"
                >
                  <p
                    class="text-[10px] uppercase tracking-wider font-semibold text-n-slate-10"
                  >
                    {{ t('CONVERSATION.FORWARD.CONTACTS_LABEL') }}
                  </p>
                </div>

                <div
                  v-for="item in filteredList"
                  :key="item.id"
                  class="flex items-center gap-3 px-4 py-2.5 cursor-pointer transition-colors hover:bg-n-slate-3"
                  :class="{
                    'bg-n-iris-3/60 dark:bg-n-iris-4/20': isItemSelected(
                      item.id
                    ),
                  }"
                  @click="toggleItem(item.id)"
                >
                  <div class="relative shrink-0">
                    <Avatar :name="item.name" :src="item.avatar" :size="40" />
                    <span
                      v-if="isItemSelected(item.id)"
                      class="absolute -bottom-0.5 -right-0.5 flex items-center justify-center size-[18px] rounded-full bg-n-brand text-white ring-2 ring-n-background"
                    >
                      <Icon icon="i-lucide-check" class="size-2.5" />
                    </span>
                  </div>

                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2">
                      <p class="text-sm font-medium text-n-slate-12 truncate">
                        {{ item.name }}
                      </p>
                      <span
                        v-if="item.type === 'contact'"
                        class="shrink-0 text-[10px] font-medium px-1.5 py-0.5 rounded bg-n-amber-4 text-n-amber-12"
                      >
                        {{ t('CONVERSATION.FORWARD.NEW_CONVERSATION') }}
                      </span>
                    </div>
                    <p class="text-xs text-n-slate-11 truncate">
                      {{ item.phone || item.email }}
                    </p>
                    <p
                      v-if="item.lastMessage"
                      class="text-xs text-n-slate-10 truncate"
                    >
                      {{ item.lastMessage }}
                    </p>
                  </div>
                </div>
              </template>

              <div
                v-if="isSearching"
                class="flex items-center justify-center py-4 text-n-slate-10 text-xs"
              >
                <Icon
                  icon="i-lucide-loader-2"
                  class="size-4 animate-spin mr-1"
                />
                {{ t('CONVERSATION.FORWARD.SEARCHING') }}
              </div>
            </div>

            <!-- Message Preview (collapsible) -->
            <div class="border-t border-n-weak">
              <button
                class="flex items-center gap-2 w-full px-4 py-2.5 text-left hover:bg-n-slate-3 transition-colors"
                @click="showMessagePicker = !showMessagePicker"
              >
                <Icon
                  :icon="
                    showMessagePicker
                      ? 'i-lucide-chevron-down'
                      : 'i-lucide-chevron-right'
                  "
                  class="size-4 text-n-slate-10"
                />
                <span class="text-xs font-medium text-n-slate-11">
                  {{ messagePreviewLabel }}
                  {{ `(${pickedMessageIds.length})` }}
                </span>
              </button>

              <div
                v-if="showMessagePicker"
                class="max-h-48 overflow-y-auto border-t border-n-weak"
              >
                <div
                  v-if="messageCandidates.length === 0"
                  class="text-sm text-n-slate-10 py-4 text-center"
                >
                  {{ t('CONVERSATION.FORWARD.NO_MESSAGES') }}
                </div>
                <div
                  v-for="msg in messageCandidates"
                  :key="`msg-${msg.id}`"
                  class="flex items-start gap-2.5 px-4 py-2 cursor-pointer transition-colors hover:bg-n-slate-3"
                  :class="{
                    'bg-n-iris-3/60 dark:bg-n-iris-4/20': isMessageSelected(
                      msg.id
                    ),
                  }"
                  @click="toggleMessageSelection(msg.id)"
                >
                  <input
                    type="checkbox"
                    class="mt-0.5 size-4 text-n-brand rounded border-n-weak focus:ring-n-brand pointer-events-none"
                    :checked="isMessageSelected(msg.id)"
                  />
                  <p class="flex-1 text-xs text-n-slate-11 line-clamp-2">
                    {{ getMessagePreview(msg) }}
                  </p>
                </div>
              </div>

              <div
                v-if="
                  !showMessagePicker && selectedMessagePreviewList.length > 0
                "
                class="px-4 pb-2"
              >
                <div
                  v-for="(preview, index) in selectedMessagePreviewList.slice(
                    0,
                    2
                  )"
                  :key="`preview-${index}`"
                  class="text-xs text-n-slate-11 truncate py-0.5"
                >
                  {{ preview }}
                </div>
                <p
                  v-if="selectedMessagePreviewList.length > 2"
                  class="text-[10px] text-n-slate-10"
                >
                  {{
                    t('CONVERSATION.FORWARD.MORE_MESSAGES', {
                      count: selectedMessagePreviewList.length - 2,
                    })
                  }}
                </p>
              </div>
            </div>

            <!-- Footer -->
            <div
              class="flex items-center justify-end gap-2 px-4 py-3 border-t border-n-weak"
            >
              <button
                class="px-4 py-2 text-sm font-medium text-n-slate-11 rounded-lg hover:bg-n-slate-3 transition-colors"
                @click="handleClose"
              >
                {{ t('CONVERSATION.FORWARD.CANCEL') }}
              </button>
              <button
                :disabled="
                  selectedItems.length === 0 ||
                  pickedMessageIds.length === 0 ||
                  isForwarding
                "
                class="flex items-center gap-2 px-5 py-2 text-sm font-medium text-white bg-n-brand rounded-lg hover:bg-n-brand disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                @click="handleForward"
              >
                <Icon
                  v-if="isForwarding"
                  icon="i-lucide-loader-2"
                  class="size-4 animate-spin"
                />
                {{
                  isForwarding
                    ? t('CONVERSATION.FORWARD.FORWARDING')
                    : t('CONVERSATION.FORWARD.FORWARD')
                }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
