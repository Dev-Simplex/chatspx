<script setup>
import { defineProps, computed, ref, watch } from 'vue';
import { isSameDay } from 'date-fns';
import Message from './Message.vue';
import DateSeparator from 'shared/components/DateSeparator.vue';
import { MESSAGE_TYPES, ATTACHMENT_TYPES } from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

/**
 * Props definition for the component
 * @typedef {Object} Props
 * @property {Array} readMessages - Array of read messages
 * @property {Array} unReadMessages - Array of unread messages
 * @property {Number} currentUserId - ID of the current user
 * @property {Boolean} isAnEmailChannel - Whether this is an email channel
 * @property {Object} inboxSupportsReplyTo - Inbox reply support configuration
 * @property {Array} messages - Array of all messages [These are not in camelcase]
 */
const props = defineProps({
  currentUserId: {
    type: Number,
    required: true,
  },
  firstUnreadId: {
    type: Number,
    default: null,
  },
  isAnEmailChannel: {
    type: Boolean,
    default: false,
  },
  inboxSupportsReplyTo: {
    type: Object,
    default: () => ({ incoming: false, outgoing: false }),
  },
  messages: {
    type: Array,
    default: () => [],
  },
  isWahaInbox: {
    type: Boolean,
    default: false,
  },
  isForwardMode: {
    type: Boolean,
    default: false,
  },
  selectedMessageIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['forward', 'toggle-forward-selection']);

// Track known message IDs so only NEW messages get the entrance animation
const knownMessageIds = ref(new Set());
const newMessageIds = ref(new Set());
const initialLoadDone = ref(false);

watch(
  () => props.messages,
  newMessages => {
    if (!initialLoadDone.value) {
      // First load (history) — mark all as known, no animation
      knownMessageIds.value = new Set(newMessages.map(m => m.id));
      initialLoadDone.value = true;
    } else {
      // Subsequent updates — find truly new messages
      const freshIds = new Set();
      newMessages.forEach(m => {
        if (!knownMessageIds.value.has(m.id)) {
          freshIds.add(m.id);
          knownMessageIds.value.add(m.id);
        }
      });
      newMessageIds.value = freshIds;
    }
  },
  { immediate: true }
);

const isNewMessage = messageId => {
  return newMessageIds.value.has(messageId);
};

const CAMEL_CASE_OPTIONS = {
  deep: true,
  stopPaths: ['content_attributes.translations'],
};
const camelizedMessageCache = new WeakMap();

const toCamelizedMessage = message => {
  if (!message || typeof message !== 'object') {
    return message;
  }

  const cachedValue = camelizedMessageCache.get(message);
  if (cachedValue) {
    return cachedValue;
  }

  const transformedMessage = useCamelCase(message, CAMEL_CASE_OPTIONS);
  camelizedMessageCache.set(message, transformedMessage);
  return transformedMessage;
};

const allMessages = computed(() => {
  return props.messages.map(toCamelizedMessage);
});

const replyMessagesById = computed(() => {
  return allMessages.value.reduce((messageMap, message) => {
    messageMap.set(message.id, message);
    return messageMap;
  }, new Map());
});

const isForwardSelected = messageId =>
  props.selectedMessageIds.includes(messageId);

const getSenderId = message => message.senderId ?? message.sender?.id;

const isMediaOnlyMessage = message => {
  if (!message || message.content) return false;

  const attachments = Array.isArray(message.attachments)
    ? message.attachments
    : [];

  if (attachments.length !== 1) return false;
  if (message.status === 'failed') return false;
  if (message.contentAttributes?.deleted) return false;
  if (message.contentAttributes?.isUnsupported) return false;

  return attachments.every(attachment =>
    [
      ATTACHMENT_TYPES.IMAGE,
      ATTACHMENT_TYPES.VIDEO,
      ATTACHMENT_TYPES.IG_REEL,
    ].includes(attachment.fileType)
  );
};

const canGroupMedia = (current, next) => {
  if (!isMediaOnlyMessage(current) || !isMediaOnlyMessage(next)) return false;
  if ((current.private ?? false) !== (next.private ?? false)) return false;
  if (current.messageType !== next.messageType) return false;
  if (getSenderId(current) !== getSenderId(next)) return false;

  const currentDate = new Date(current.createdAt * 1000);
  const nextDate = new Date(next.createdAt * 1000);
  if (!isSameDay(currentDate, nextDate)) return false;

  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

const buildMessageItem = message => ({
  type: 'message',
  key: `message-${message.id}`,
  message,
  sourceMessages: [message],
});

const buildMediaGroupItem = groupMessages => {
  const lastMessage = groupMessages[groupMessages.length - 1];
  const attachments = groupMessages.flatMap(
    message => message.attachments || []
  );

  return {
    type: 'media-group',
    key: `media-group-${groupMessages[0].id}-${lastMessage.id}`,
    message: {
      ...lastMessage,
      attachments,
      content: null,
    },
    sourceMessages: groupMessages,
  };
};

const collectMediaGroup = (startIndex, messageList) => {
  const groupMessages = [messageList[startIndex]];
  let cursor = startIndex;

  while (cursor < messageList.length - 1) {
    const current = messageList[cursor];
    const next = messageList[cursor + 1];
    if (!canGroupMedia(current, next)) break;
    groupMessages.push(next);
    cursor += 1;
  }

  return { groupMessages, lastIndex: cursor };
};

const renderItems = computed(() => {
  if (props.isForwardMode) {
    return allMessages.value.map(buildMessageItem);
  }

  const items = [];
  const messageList = allMessages.value;

  let index = 0;
  while (index < messageList.length) {
    const message = messageList[index];
    let item = buildMessageItem(message);
    let nextIndex = index + 1;

    if (isMediaOnlyMessage(message)) {
      const { groupMessages, lastIndex } = collectMediaGroup(
        index,
        messageList
      );
      if (groupMessages.length > 1) {
        item = buildMediaGroupItem(groupMessages);
        nextIndex = lastIndex + 1;
      }
    }

    items.push(item);
    index = nextIndex;
  }

  return items;
});

const getItemMessage = item => item.message;
const getItemDate = item =>
  item.sourceMessages?.[0]?.createdAt ?? item.message.createdAt;

const shouldShowUnreadBadge = item => {
  if (!props.firstUnreadId) return false;
  return item.sourceMessages.some(
    message => message.id === props.firstUnreadId
  );
};

/**
 * Determines if a message should be grouped with the next message
 * @param {Number} index - Index of the current message
 * @param {Array} searchList - Array of messages to check
 * @returns {Boolean} - Whether the message should be grouped with next
 */
const shouldGroupWithNext = (index, searchList) => {
  if (index === searchList.length - 1) return false;

  const current = getItemMessage(searchList[index]);
  const next = getItemMessage(searchList[index + 1]);

  if (next.status === 'failed') return false;

  const nextSenderId = next.senderId ?? next.sender?.id;
  const currentSenderId = current.senderId ?? current.sender?.id;
  const hasSameSender = nextSenderId === currentSenderId;

  const nextMessageType = next.messageType;
  const currentMessageType = current.messageType;

  const areBothTemplates =
    nextMessageType === MESSAGE_TYPES.TEMPLATE &&
    currentMessageType === MESSAGE_TYPES.TEMPLATE;

  if (!hasSameSender || areBothTemplates) return false;

  if (currentMessageType !== nextMessageType) return false;

  // Check if messages are in the same minute by rounding down to nearest minute
  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

/**
 * Gets the message that was replied to
 * @param {Object} parentMessage - The message containing the reply reference
 * @returns {Object|null} - The message being replied to, or null if not found
 */
const getInReplyToMessage = parentMessage => {
  if (!parentMessage) return null;

  const inReplyToMessageId = parentMessage.contentAttributes?.inReplyTo;

  if (!inReplyToMessageId) return null;

  return replyMessagesById.value.get(inReplyToMessageId) || null;
};

/**
 * Check if we should show date separator before this message
 * @param {Number} index - Index of the current message
 * @param {Array} messageList - Array of messages
 * @returns {Boolean} - Whether to show date separator
 */
const shouldShowDateSeparator = (index, messageList) => {
  if (index === 0) return true;

  const current = messageList[index];
  const previous = messageList[index - 1];

  const currentDate = new Date(getItemDate(current) * 1000);
  const previousDate = new Date(getItemDate(previous) * 1000);

  return !isSameDay(currentDate, previousDate);
};
</script>

<template>
  <ul class="px-4 bg-n-surface-1">
    <slot name="beforeAll" />
    <template v-for="(item, index) in renderItems" :key="item.key">
      <DateSeparator
        v-if="shouldShowDateSeparator(index, renderItems)"
        :date="new Date(getItemDate(item) * 1000)"
      />
      <slot v-if="shouldShowUnreadBadge(item)" name="unreadBadge" />
      <Message
        v-bind="item.message"
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(item.message)"
        :group-with-next="shouldGroupWithNext(index, renderItems)"
        :inbox-supports-reply-to="inboxSupportsReplyTo"
        :current-user-id="currentUserId"
        :is-waha-inbox="isWahaInbox"
        :is-forward-mode="isForwardMode"
        :is-forward-selected="isForwardSelected(item.message.id)"
        :is-new="isNewMessage(item.message.id)"
        data-clarity-mask="True"
        @forward="emit('forward', $event)"
        @toggle-forward-selection="emit('toggle-forward-selection', $event)"
      />
    </template>
    <slot name="after" />
  </ul>
</template>
