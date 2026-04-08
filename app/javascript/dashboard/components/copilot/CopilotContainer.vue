<script setup>
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import CopilotPanel from 'dashboard/components-next/copilot/CopilotPanel.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import wootConstants from 'dashboard/constants/globals';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import CopilotMessagesAPI from 'dashboard/api/captain/copilotMessages';
import CaptainApiKeyMissingModal from 'dashboard/components-next/copilot/CaptainApiKeyMissingModal.vue';

defineProps({
  conversationInboxType: {
    type: String,
    default: '',
  },
});

const store = useStore();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();
const { isAdmin } = useAdmin();
const captainConfigStore = useCaptainConfigStore();
const RESPONSE_TIMEOUT_MS = 30_000;
const RESPONSE_POLL_INTERVAL_MS = 2_000;

const currentUser = useMapGetter('getCurrentUser');
const assistants = useMapGetter('captainAssistants/getRecords');
const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const inboxAssistant = useMapGetter('getCopilotAssistant');
const currentChat = useMapGetter('getSelectedChat');

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const selectedCopilotThreadId = ref(null);
const messages = computed(() =>
  store.getters['copilotMessages/getMessagesByThreadId'](
    selectedCopilotThreadId.value
  )
);

const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const activeAccountId = computed(() => Number(currentAccountId.value) || null);
const isCaptainEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN_V2
  )
);

const selectedAssistantId = ref(null);
const apiKeyStatusByAccount = ref({});
const showApiKeyMissingModal = ref(false);
const apiKeyMissingModalRef = ref(null);
const isAwaitingResponse = ref(false);
const hasTimedOut = ref(false);
const lastSentMessage = ref('');
const responsePollIntervalId = ref(null);
const responseTimeoutId = ref(null);
const isSyncingThreadMessages = ref(false);

const activeAssistant = computed(() => {
  const preferredId = uiSettings.value.preferred_captain_assistant_id;

  // If the user has selected a specific assistant, it takes first preference for Copilot.
  if (preferredId) {
    const preferredAssistant = assistants.value.find(a => a.id === preferredId);
    // Return the preferred assistant if found, otherwise continue to next cases
    if (preferredAssistant) return preferredAssistant;
  }

  // If the above is not available, the assistant connected to the inbox takes preference.
  if (inboxAssistant.value) {
    const inboxMatchedAssistant = assistants.value.find(
      a => a.id === inboxAssistant.value.id
    );
    if (inboxMatchedAssistant) return inboxMatchedAssistant;
  }
  // If neither of the above is available, the first assistant in the account takes preference.
  return assistants.value[0];
});

const closeCopilotPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_copilot_panel_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

const setAssistant = async assistant => {
  selectedAssistantId.value = assistant.id;
  await updateUISettings({
    preferred_captain_assistant_id: assistant.id,
  });
};

const shouldShowCopilotPanel = computed(() => {
  const { is_copilot_panel_open: isCopilotPanelOpen } = uiSettings.value;
  return (
    isCaptainEnabled.value && isCopilotPanelOpen && !uiFlags.value.fetchingList
  );
});

const clearResponseTracking = () => {
  if (responsePollIntervalId.value) {
    clearInterval(responsePollIntervalId.value);
    responsePollIntervalId.value = null;
  }

  if (responseTimeoutId.value) {
    clearTimeout(responseTimeoutId.value);
    responseTimeoutId.value = null;
  }

  isAwaitingResponse.value = false;
  isSyncingThreadMessages.value = false;
};

const stopAwaitingResponse = () => {
  clearResponseTracking();
};

const handleReset = () => {
  selectedCopilotThreadId.value = null;
  lastSentMessage.value = '';
  clearResponseTracking();
  hasTimedOut.value = false;
};

const openApiKeyMissingModal = async () => {
  if (showApiKeyMissingModal.value) return;
  showApiKeyMissingModal.value = true;
  await nextTick();
  apiKeyMissingModalRef.value?.open();
};

const closeApiKeyMissingModal = () => {
  showApiKeyMissingModal.value = false;
};

const ensureCopilotApiKeyConfigured = async () => {
  const accountId = activeAccountId.value;
  if (!accountId) return false;

  const cachedStatus = apiKeyStatusByAccount.value[accountId];
  if (cachedStatus === true) return true;

  try {
    await captainConfigStore.fetch({
      accountId,
      force: cachedStatus === false,
    });
    const configured = Boolean(captainConfigStore.llmConnection?.configured);
    apiKeyStatusByAccount.value = {
      ...apiKeyStatusByAccount.value,
      [accountId]: configured,
    };

    if (!configured) {
      await openApiKeyMissingModal();
    }

    return configured;
  } catch {
    await openApiKeyMissingModal();
    return false;
  }
};

const getThreadMessages = threadId => {
  return store.getters['copilotMessages/getMessagesByThreadId'](threadId);
};

const isAssistantReplyComplete = threadId => {
  const threadMessages = getThreadMessages(threadId);
  if (!threadMessages?.length) return false;
  const lastMessage = threadMessages[threadMessages.length - 1];
  return lastMessage?.message_type === 'assistant';
};

const syncThreadMessages = async threadId => {
  if (!threadId || isSyncingThreadMessages.value) return;

  isSyncingThreadMessages.value = true;
  try {
    const response = await CopilotMessagesAPI.get(threadId);
    const records = response?.data?.payload || [];
    records.forEach(record => store.dispatch('copilotMessages/upsert', record));

    if (isAssistantReplyComplete(threadId)) {
      stopAwaitingResponse();
    }
  } catch (error) {
    // We keep websocket as primary source and polling as best-effort fallback.
    // Ignore transient sync errors to avoid blocking the UI.
  } finally {
    isSyncingThreadMessages.value = false;
  }
};

const startAwaitingResponse = threadId => {
  const normalizedThreadId = Number(threadId) || null;
  if (!normalizedThreadId) return;

  hasTimedOut.value = false;
  clearResponseTracking();
  isAwaitingResponse.value = true;

  syncThreadMessages(normalizedThreadId);

  responsePollIntervalId.value = setInterval(() => {
    syncThreadMessages(normalizedThreadId);
  }, RESPONSE_POLL_INTERVAL_MS);

  responseTimeoutId.value = setTimeout(() => {
    stopAwaitingResponse();
    hasTimedOut.value = true;
  }, RESPONSE_TIMEOUT_MS);
};

const sendMessage = async message => {
  if (!activeAssistant.value?.id) return;
  if (!message?.trim()) return;

  const isConfigured = await ensureCopilotApiKeyConfigured();
  if (!isConfigured) return;

  const sanitizedMessage = message.trim();
  lastSentMessage.value = sanitizedMessage;
  hasTimedOut.value = false;

  try {
    let threadId = selectedCopilotThreadId.value;

    if (selectedCopilotThreadId.value) {
      await store.dispatch('copilotMessages/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: currentChat.value?.id,
        threadId: selectedCopilotThreadId.value,
        message: sanitizedMessage,
      });
    } else {
      const response = await store.dispatch('copilotThreads/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: currentChat.value?.id,
        message: sanitizedMessage,
      });
      selectedCopilotThreadId.value = response.id;
      threadId = response.id;
    }

    startAwaitingResponse(threadId);
  } catch (error) {
    stopAwaitingResponse();
    const errorCode =
      error?.code || error?.details?.code || error?.response?.data?.code;
    if (errorCode === 'captain_api_key_missing') {
      apiKeyStatusByAccount.value = {
        ...apiKeyStatusByAccount.value,
        [activeAccountId.value]: false,
      };
      await openApiKeyMissingModal();
      return;
    }

    useAlert(error.message);
  }
};

const retryLastMessage = async () => {
  if (!lastSentMessage.value) return;
  hasTimedOut.value = false;
  await sendMessage(lastSentMessage.value);
};

watch(messages, newMessages => {
  if (!isAwaitingResponse.value || !newMessages?.length) return;

  const lastMessage = newMessages[newMessages.length - 1];
  if (lastMessage?.message_type === 'assistant') {
    stopAwaitingResponse();
  }
});

onMounted(() => {
  if (isCaptainEnabled.value) {
    store.dispatch('captainAssistants/get');
  }
});

onBeforeUnmount(() => {
  clearResponseTracking();
});
</script>

<template>
  <div
    v-if="shouldShowCopilotPanel"
    v-on-click-outside="() => closeCopilotPanel()"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': shouldShowCopilotPanel,
        'md:hidden': !shouldShowCopilotPanel,
      },
    ]"
  >
    <CopilotPanel
      :messages="messages"
      :support-agent="currentUser"
      :conversation-inbox-type="conversationInboxType"
      :assistants="assistants"
      :active-assistant="activeAssistant"
      :is-awaiting-response="isAwaitingResponse"
      :has-timed-out="hasTimedOut"
      :timeout-message="t('CAPTAIN.COPILOT.RESPONSE_TIMEOUT_BODY')"
      @set-assistant="setAssistant"
      @send-message="sendMessage"
      @retry="retryLastMessage"
      @reset="handleReset"
    />
    <CaptainApiKeyMissingModal
      v-if="showApiKeyMissingModal"
      ref="apiKeyMissingModalRef"
      :is-admin="isAdmin"
      :account-id="activeAccountId"
      @close="closeApiKeyMissingModal"
    />
  </div>
  <template v-else />
</template>
