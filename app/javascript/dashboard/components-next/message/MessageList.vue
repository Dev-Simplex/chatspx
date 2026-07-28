<script setup>
import { defineProps, computed, ref, watch } from 'vue';
import { isSameDay } from 'date-fns';
import { useI18n } from 'vue-i18n';
import Message from './Message.vue';
import MessageReactions from './MessageReactions.vue';
import DateSeparator from 'shared/components/DateSeparator.vue';
import { MESSAGE_TYPES, ATTACHMENT_TYPES } from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useStore } from 'dashboard/composables/store';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import { authorIdentityKey } from 'dashboard/helper/whatsappGroupHelper';
import { collectWhatsAppReactions } from 'dashboard/helper/whatsappReactionHelper';

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

const store = useStore();
const { t } = useI18n();
const { isMessageRestricted } = useAgentIsolation();
const currentChat = computed(() => store.getters.getSelectedChat || {});
const currentInbox = computed(() => {
  const inboxId = currentChat.value?.inbox_id;
  return inboxId ? store.getters['inboxes/getInbox'](inboxId) : {};
});

// Isolamento por agente: não expor no preview de reply/quote uma mensagem de outro agente
// (que possa ter entrado no store via websocket). Restrita → fica de fora do mapa, o
// getInReplyToMessage devolve null e o quote não é renderizado.
const replyMessagesById = computed(() => {
  return allMessages.value.reduce((messageMap, message) => {
    if (!isMessageRestricted(message, currentInbox.value)) {
      messageMap.set(message.id, message);
    }
    return messageMap;
  }, new Map());
});

const isForwardSelected = messageId =>
  props.selectedMessageIds.includes(messageId);

/**
 * Reação de WhatsApp chega como MENSAGEM de texto ("*Reagiu com* 👍") — uma bolha por
 * pessoa que reagiu. O índice abaixo tira essas mensagens do fio e devolve o mesmo dado
 * como chip ancorado na bolha reagida. Ver `whatsappReactionHelper` para o contrato.
 *
 * Não é condicionado a grupo: a reação polui a conversa 1:1 do mesmo jeito. O que
 * condiciona é a mensagem SER uma reação — nada além disso muda de comportamento.
 */
const reactionIndex = computed(() =>
  collectWhatsAppReactions(allMessages.value)
);

/**
 * O tooltip nomeia quem reagiu. Só nome ou telefone formatado chegam até aqui: o
 * identificador técnico do participante é removido no helper e não existe neste dado.
 * @param {Array<{emoji: String, count: Number, authors: String[]}>} chips
 */
const decorateChips = chips =>
  chips.map(chip => ({
    emoji: chip.emoji,
    count: chip.count,
    title: chip.authors.length
      ? chip.authors.join(', ')
      : t('CONVERSATION.REACTIONS.FROM_WHATSAPP'),
  }));

const reactionsFor = message => {
  const chips = reactionIndex.value.reactionsByMessageId.get(message.id);
  return chips ? decorateChips(chips) : [];
};

const visibleMessages = computed(() => {
  const hidden = reactionIndex.value.hiddenMessageIds;
  if (!hidden.size) return allMessages.value;

  return allMessages.value.filter(message => !hidden.has(message.id));
});

// Espelha `Conversation#group?` (app/models/conversation.rb) — o backend é o ponto
// único de verdade, mas ainda não serializa o resultado; enquanto isso o front repete
// a mesma heurística de JID. A WAHA não seta `additional_attributes['type']`, ela
// identifica o grupo pelo JID do contato terminando em `@g.us`.
const WHATSAPP_GROUP_JID_SUFFIX = '@g.us';

const endsWithGroupJid = value =>
  String(value ?? '').endsWith(WHATSAPP_GROUP_JID_SUFFIX);

const isGroupConversation = computed(() => {
  const chat = currentChat.value;
  if (chat.additional_attributes?.type === 'group') return true;

  const contact = chat.meta?.sender;
  if (!contact) return false;
  if (endsWithGroupJid(contact.identifier)) return true;

  const custom = contact.custom_attributes || {};
  return [custom.waha_whatsapp_chat_id, custom.waha_whatsapp_jid].some(
    endsWithGroupJid
  );
});

// Autor real da mensagem dentro do grupo, gravado na ingestão (contrato
// `content_attributes.group_sender`). Chega camelizado por `toCamelizedMessage`;
// o fallback snake cobre payloads que não passaram pela camelização.
const groupSenderOf = message =>
  message?.contentAttributes?.groupSender ??
  message?.contentAttributes?.group_sender ??
  null;

/**
 * Em conversa de grupo o `senderId` é SEMPRE o contato-grupo — igual para todo mundo.
 * Agrupar por ele junta pessoas diferentes na mesma bolha visual. Quem responde por
 * "é a mesma pessoa?" é a identidade estável do participante (lid > phone > name).
 * Sem identidade conhecida (mensagem legada, autor não resolvido) não se agrupa:
 * é preferível uma bolha a mais do que atribuir a fala a quem não a disse.
 * @returns {Boolean}
 */
const hasSameGroupAuthor = (current, next) => {
  const currentKey = authorIdentityKey(groupSenderOf(current) || {});
  const nextKey = authorIdentityKey(groupSenderOf(next) || {});

  if (!currentKey || !nextKey) return false;

  return currentKey === nextKey;
};

const isIncoming = message => message?.messageType === MESSAGE_TYPES.INCOMING;

const breaksGroupAuthorBlock = (current, next) => {
  if (!isGroupConversation.value) return false;
  if (!isIncoming(current) || !isIncoming(next)) return false;

  // Nenhuma das duas tem autor estruturado: é histórico legado (o autor ainda está
  // dentro do texto, visível em cada bolha) ou o chat interno, que compartilha esta
  // lista. Nesses casos vale a regra de hoje — a correção age só onde há dado novo.
  if (!groupSenderOf(current) && !groupSenderOf(next)) return false;

  return !hasSameGroupAuthor(current, next);
};

const getSenderId = message => message.senderId ?? message.sender?.id;

const isMediaOnlyMessage = message => {
  if (!message || message.content) return false;

  const attachments = Array.isArray(message.attachments)
    ? message.attachments
    : [];

  if (attachments.length !== 1) return false;
  if (message.status === 'failed') return false;
  // Bolha otimista em upload renderiza pela bolha dedicada (com anel de
  // progresso + clique bloqueado); não agrupar, senão cai no MediaGrid sem isso.
  if (attachments.some(a => a.uploadStatus === 'uploading')) return false;
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
  if (breaksGroupAuthorBlock(current, next)) return false;

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

/**
 * Reação cujo alvo não está na página carregada (ou que veio sem `in_reply_to`). Some do
 * fio como bolha, mas continua visível como chip solto — esconder seria apagar
 * informação que o agente enxerga hoje.
 */
const buildStandaloneReactionItem = (message, chips) => ({
  type: 'reaction',
  key: `reaction-${message.id}`,
  message,
  sourceMessages: [message],
  chips: decorateChips(chips),
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
    return visibleMessages.value.map(buildMessageItem);
  }

  const items = [];
  const messageList = visibleMessages.value;
  const { standaloneReactions } = reactionIndex.value;

  let index = 0;
  while (index < messageList.length) {
    const message = messageList[index];
    let item = buildMessageItem(message);
    let nextIndex = index + 1;

    const standaloneChips = standaloneReactions.get(message.id);

    if (standaloneChips) {
      item = buildStandaloneReactionItem(message, standaloneChips);
    } else if (isMediaOnlyMessage(message)) {
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

  // Chip solto de reação não faz parte de bloco de bolhas — nem abre nem fecha um.
  if (searchList[index].type === 'reaction') return false;
  if (searchList[index + 1].type === 'reaction') return false;

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

  // Em grupo o mesmo `senderId` não significa a mesma pessoa — ver `hasSameGroupAuthor`.
  if (breaksGroupAuthorBlock(current, next)) return false;

  // Check if messages are in the same minute by rounding down to nearest minute
  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

/**
 * Espelho de `shouldGroupWithNext` olhando para trás. O WhatsApp mostra nome e avatar
 * do autor na PRIMEIRA mensagem do bloco (o Chatwoot mostra o avatar na última), então
 * a bolha precisa saber se ela abre ou continua um bloco.
 * @param {Number} index - Index of the current message
 * @param {Array} searchList - Array of messages to check
 * @returns {Boolean} - Whether the message continues the previous message's block
 */
const shouldGroupWithPrevious = (index, searchList) => {
  if (index === 0) return false;

  return shouldGroupWithNext(index - 1, searchList);
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
      <!-- Reação sem bolha para ancorar: chip solto, discreto, alinhado com o lado de
           quem reagiu. Nunca uma bolha de texto. -->
      <div
        v-if="item.type === 'reaction'"
        class="flex w-full mb-2"
        :class="
          item.message.messageType === MESSAGE_TYPES.OUTGOING
            ? 'justify-end'
            : 'justify-start ltr:pl-9 rtl:pr-9'
        "
      >
        <MessageReactions readonly mode="chips" :chips="item.chips" />
      </div>
      <Message
        v-else
        v-bind="item.message"
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(item.message)"
        :group-with-next="shouldGroupWithNext(index, renderItems)"
        :group-with-previous="shouldGroupWithPrevious(index, renderItems)"
        :is-group-conversation="isGroupConversation"
        :whatsapp-reactions="reactionsFor(item.message)"
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
