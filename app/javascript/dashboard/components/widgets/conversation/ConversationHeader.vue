<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Thumbnail from '../Thumbnail.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ConversationMessageSearch from './ConversationMessageSearch.vue';
import ConversationStatusActions from 'dashboard/components-next/Conversation/ConversationStatusActions.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNowStrict } from 'date-fns';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();
const { uiSettings, updateUISettings } = useUISettings();
const showMessageSearch = ref(false);

const toggleContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: !uiSettings.value.is_contact_sidebar_open,
    is_copilot_panel_open: false,
  });
};

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_unattended: 'unattended',
    conversation_through_unread: 'unread',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() => {
  const senderId = props.chat?.meta?.sender?.id;
  if (!senderId) return {};
  return store.getters['contacts/getContact'](senderId);
});

const typingUsers = computed(() => {
  const id = currentChat.value?.id;
  if (!id) return [];
  const fn = store.getters['conversationTypingStatus/getUserList'];
  return fn ? fn(id) || [] : [];
});

const isContactTyping = computed(() =>
  typingUsers.value.some(u => u?.type === 'contact' || u?.type === 'Contact')
);

const lastSeenAt = computed(() => {
  return (
    currentContact.value?.last_seen_at ||
    chatMetadata.value?.sender?.last_seen_at ||
    null
  );
});

const isContactOnline = computed(() => {
  if (currentContact.value?.availability_status === 'online') return true;
  const ts = lastSeenAt.value;
  if (!ts) return false;
  return Date.now() / 1000 - Number(ts) < 30;
});

const lastSeenLabel = computed(() => {
  if (!lastSeenAt.value) return '';
  try {
    const seenDate = new Date(Number(lastSeenAt.value) * 1000);
    return t('CONVERSATION.HEADER.LAST_SEEN', {
      relative: formatDistanceToNowStrict(seenDate, { addSuffix: true }),
    });
  } catch {
    return '';
  }
});

const presenceText = computed(() => {
  if (isContactTyping.value) return t('CONVERSATION.HEADER.TYPING');
  if (isContactOnline.value) return t('CONVERSATION.HEADER.ONLINE');
  return lastSeenLabel.value;
});

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

// --- WhatsApp 24h window timer -------------------------------------------
// Re-render every 60s so "remaining" stays fresh without per-component timers.
const nowTick = ref(Date.now());
let nowIntervalId = null;

onMounted(() => {
  nowIntervalId = setInterval(() => {
    nowTick.value = Date.now();
  }, 60 * 1000);
});

onBeforeUnmount(() => {
  if (nowIntervalId) {
    clearInterval(nowIntervalId);
    nowIntervalId = null;
  }
});

const isWhatsAppChannel = computed(() => {
  const channel = inbox.value?.channel_type || '';
  const medium = inbox.value?.medium || '';
  // Native WhatsApp (Cloud + 360Dialog) uses Channel::Whatsapp; Twilio SMS/WhatsApp
  // shares Channel::TwilioSms with medium === 'whatsapp'.
  return (
    channel === 'Channel::Whatsapp' ||
    (channel === 'Channel::TwilioSms' && medium === 'whatsapp')
  );
});

const lastIncomingMessage = computed(() => {
  const messages = props.chat?.messages || [];
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const msg = messages[i];
    if (msg && msg.message_type === MESSAGE_TYPE.INCOMING && !msg.private) {
      return msg;
    }
  }
  return null;
});

const whatsAppWindowRemainingMs = computed(() => {
  if (!isWhatsAppChannel.value) return null;
  const msg = lastIncomingMessage.value;
  if (!msg) return null;
  // Chatwoot API exposes `created_at` as seconds-since-epoch.
  const createdAt = Number(msg.created_at);
  if (!createdAt) return null;
  const expiresAt = createdAt * 1000 + 24 * 60 * 60 * 1000;
  return expiresAt - nowTick.value;
});

const whatsAppWindowDisplay = computed(() => {
  const remaining = whatsAppWindowRemainingMs.value;
  if (remaining === null) return null;

  if (remaining <= 0) {
    return {
      level: 'expired',
      text: t('CONVERSATION.WHATSAPP_WINDOW.EXPIRED'),
    };
  }

  const totalMinutes = Math.floor(remaining / (60 * 1000));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (remaining >= 12 * 60 * 60 * 1000) {
    return {
      level: 'ok',
      text: t('CONVERSATION.WHATSAPP_WINDOW.HOURS_LEFT', { hours }),
    };
  }

  if (remaining >= 2 * 60 * 60 * 1000) {
    const label = minutes ? `${hours}h ${minutes}min` : `${hours}h`;
    return {
      level: 'warning',
      text: t('CONVERSATION.WHATSAPP_WINDOW.EXPIRING', { time: label }),
    };
  }

  const label = hours ? `${hours}h ${minutes}min` : `${minutes}min`;
  return {
    level: 'urgent',
    text: t('CONVERSATION.WHATSAPP_WINDOW.EXPIRING', { time: label }),
  };
});

const whatsAppWindowClass = computed(() => {
  const display = whatsAppWindowDisplay.value;
  if (!display) return '';
  switch (display.level) {
    case 'urgent':
      return 'text-red-600 dark:text-red-400 font-semibold';
    case 'expired':
      return 'text-red-700 dark:text-red-400 font-semibold';
    case 'warning':
      return 'text-amber-600 dark:text-amber-400';
    case 'ok':
    default:
      return 'text-n-slate-11';
  }
});

const whatsAppWindowIcon = computed(() => {
  const display = whatsAppWindowDisplay.value;
  if (!display) return '';
  return display.level === 'expired'
    ? 'i-lucide-triangle-alert'
    : 'i-lucide-timer';
});

// Status badge agora é informativo (read-only) — ações de mudança de status
// ficam em ResolveAction (botão primário) + MoreActions (kebab).
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex items-center justify-between flex-shrink-0 w-full px-4 bg-n-background dark:bg-n-solid-1 border-b border-n-weak wa-conversation-header"
  >
    <div class="flex items-center gap-3 min-w-0 flex-1">
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-1 rtl:ml-1"
      />
      <Thumbnail
        :src="currentContact.thumbnail"
        :username="currentContact.name"
        :status="
          isContactOnline ? 'online' : currentContact.availability_status
        "
        size="40px"
        class="flex-shrink-0"
        allow-preview
      />
      <div class="flex flex-col items-start min-w-0 overflow-hidden">
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="wa-contact-name truncate text-n-slate-12 cursor-pointer hover:text-n-brand-default transition-colors"
            role="button"
            tabindex="0"
            @click="toggleContactPanel"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>
        <div
          v-if="presenceText"
          class="wa-contact-presence text-[12px] leading-tight truncate"
          :class="
            isContactTyping || isContactOnline
              ? 'text-n-teal-11'
              : 'text-n-slate-11'
          "
        >
          {{ presenceText }}
        </div>

        <div
          v-if="hasMultipleInboxes || isSnoozed || whatsAppWindowDisplay"
          class="wa-contact-subtitle flex items-center gap-2 overflow-hidden text-ellipsis whitespace-nowrap"
        >
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span v-if="isSnoozed" class="font-medium text-n-amber-10">
            {{ snoozedDisplayText }}
          </span>
          <span
            v-if="whatsAppWindowDisplay"
            v-tooltip="$t('CONVERSATION.WHATSAPP_WINDOW.TOOLTIP')"
            class="inline-flex items-center gap-1 whitespace-nowrap"
            :class="whatsAppWindowClass"
          >
            <span class="size-3" :class="whatsAppWindowIcon" />
            {{ whatsAppWindowDisplay.text }}
          </span>
        </div>
      </div>
    </div>
    <div class="flex items-center gap-1 flex-shrink-0">
      <ConversationStatusActions
        v-if="currentChat.id"
        :chat="currentChat"
        class="hidden md:inline-flex"
      />
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <ButtonV4
        v-tooltip="$t('SEARCH.SEARCH_IN_CONVERSATION')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-search"
        class="wa-header-icon-btn"
        @click="showMessageSearch = true"
      />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
    <ConversationMessageSearch
      v-if="currentChat.id"
      :conversation-id="currentChat.id"
      :show="showMessageSearch"
      @close="showMessageSearch = false"
    />
  </div>
</template>
