<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';

import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import InboxEmptyState from './InboxEmptyState.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

const route = useRoute();
const store = useStore();
const { uiSettings } = useUISettings();

const isConversationLoading = ref(false);

const notification = useMapGetter('notifications/getFilteredNotifications');
const currentChat = useMapGetter('getSelectedChat');
const conversationById = useMapGetter('getConversationById');
const uiFlags = useMapGetter('notifications/getUIFlags');

const inboxId = computed(() => Number(route.params.inboxId));
const conversationId = computed(() => Number(route.params.id));

const activeSortOrder = computed(() => {
  const { inbox_filter_by: filterBy = {} } = uiSettings.value;
  const { sort_by: sortBy } = filterBy;
  return sortBy || 'desc';
});

const notifications = computed(() => {
  return notification.value({
    sortOrder: activeSortOrder.value,
  });
});

const showEmptyState = computed(() => {
  return (
    !conversationId.value ||
    (!notifications.value?.length && uiFlags.value.isFetching)
  );
});

const isContactPanelOpen = computed(() => {
  if (currentChat.value.id) {
    const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;
    return isContactSidebarOpen;
  }
  return false;
});

const findConversation = () => {
  return conversationById.value(conversationId.value);
};

const setActiveChat = async () => {
  const selectedConversation = findConversation();
  if (!selectedConversation) return;

  try {
    await store.dispatch('setActiveChat', { data: selectedConversation });
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
  } catch {
    // error
  }
};

const fetchConversationById = async () => {
  if (!conversationId.value) return;

  store.dispatch('clearSelectedState');
  const existingChat = findConversation();

  if (existingChat) {
    await setActiveChat();
    return;
  }

  isConversationLoading.value = true;

  try {
    await store.dispatch('getConversation', conversationId.value);
    await setActiveChat();
  } catch {
    // error
  } finally {
    isConversationLoading.value = false;
  }
};

// Navegação prev/next entre notificações foi removida junto com o
// InboxItemHeader — user navega pela lista lateral, igual conversation normal.

watch(
  conversationId,
  (newVal, oldVal) => {
    if (newVal !== oldVal) {
      fetchConversationById();
    }
  },
  { immediate: true }
);

onMounted(async () => {
  await store.dispatch('agents/get');
});
</script>

<template>
  <div class="h-full w-full flex-1">
    <div v-if="showEmptyState" class="flex w-full h-full">
      <InboxEmptyState
        :empty-state-message="$t('INBOX.LIST.NO_MESSAGES_AVAILABLE')"
      />
    </div>
    <div v-else class="flex flex-col w-full h-full">
      <!-- InboxItemHeader removido: tela espelha a conversation normal,
           sem header extra (ConversationBox já traz o header da conversa). -->
      <div
        v-if="isConversationLoading"
        class="flex items-center flex-1 my-4 justify-center bg-n-solid-1"
      >
        <Spinner class="text-n-brand" />
      </div>
      <div v-else class="flex h-full min-w-0">
        <ConversationBox
          class="flex-1 [&.conversation-details-wrap]:!border-0"
          is-inbox-view
          :inbox-id="inboxId"
          :is-on-expanded-layout="false"
        >
          <SidepanelSwitch v-if="currentChat.id" />
        </ConversationBox>
        <ConversationSidebar
          v-if="isContactPanelOpen"
          :current-chat="currentChat"
        />
      </div>
    </div>
  </div>
</template>
