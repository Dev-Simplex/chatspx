<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { useMapGetter } from 'dashboard/composables/store';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import { aiAccentVars } from 'dashboard/helper/aiAccent';

import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, default: null },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);
const currentUser = useMapGetter('getCurrentUser');
const getContactById = useMapGetter('contacts/getContact');
const selectedChat = useMapGetter('getSelectedChat');
const getInboxById = useMapGetter('inboxes/getInbox');
const inboxesList = useMapGetter('inboxes/getInboxes');
const selectedInbox = useMapGetter('getSelectedInbox');
const { t } = useI18n();
const { isMessageRestricted } = useAgentIsolation();

const unreadCount = computed(() => props.chat.unread_count || 0);
const hasUnread = computed(() => unreadCount.value > 0);
const chatMetadata = computed(() => props.chat.meta || {});

// Quem renderiza o card passa so `:chat` (ConversationItem e ContactConversations).
// A prop `currentContact` existe como override — sem ela, o contato sai da propria
// conversa e cai num objeto vazio nomeado, nunca em undefined: o template le
// `.name` direto, e um undefined aqui derruba a lista inteira no render.
const resolvedContact = computed(() => {
  if (props.currentContact) return props.currentContact;

  const raw =
    props.chat.contact ||
    chatMetadata.value.contact ||
    chatMetadata.value.sender ||
    props.chat.sender ||
    props.chat.meta?.sender;

  if (!raw)
    return {
      id: null,
      name: 'Unknown',
      thumbnail: '',
      availability_status: 'offline',
    };

  const id = raw.id || null;
  const storeContact = id ? getContactById.value(id) : null;

  return {
    id,
    name: storeContact?.name || raw.name || raw.full_name || 'Unknown',
    thumbnail:
      storeContact?.thumbnail ||
      raw.thumbnail ||
      raw.avatar_url ||
      raw.avatar ||
      raw.profile_image_url ||
      '',
    availability_status:
      storeContact?.availability_status || raw.availability_status || 'offline',
  };
});

// Mesma historia de `resolvedContact`: estes quatro eram computed antes de virarem
// prop, e nenhum pai os passa. Com o default vazio o card nao quebra — apenas some
// com o chip de IA, o nome do responsavel, o nome da caixa e o destaque da conversa
// aberta, tudo em silencio. E `inbox` alimenta `isMessageRestricted`, o isolamento
// por agente. As props seguem valendo como override (os specs usam).
const resolvedAssignee = computed(() =>
  props.assignee && Object.keys(props.assignee).length
    ? props.assignee
    : chatMetadata.value.assignee || {}
);

const resolvedInbox = computed(() =>
  props.inbox && Object.keys(props.inbox).length
    ? props.inbox
    : getInboxById.value(props.chat.inbox_id) || {}
);

const resolvedIsActiveChat = computed(
  () => props.isActiveChat || selectedChat.value?.id === props.chat.id
);

const resolvedShowInboxName = computed(
  () =>
    props.showInboxName ||
    (!selectedInbox.value && (inboxesList.value?.length || 0) > 1)
);

const hasValidContent = message => {
  if (!message) return false;
  const hasContent = String(message.content || '').trim().length > 0;
  const hasAttachments = message.attachments?.length > 0;
  return hasContent || hasAttachments || message.private === true;
};

const lastMessageInChat = computed(() => {
  const lastMessage = getLastMessage(props.chat);
  if (lastMessage) return lastMessage;

  return [
    props.chat.last_non_activity_message,
    chatMetadata.value.last_non_activity_message,
    props.chat.last_message,
    chatMetadata.value.last_message,
    props.chat.last_activity_message,
    chatMetadata.value.last_activity_message,
  ].find(hasValidContent);
});

const previewMessage = computed(() => {
  const message = lastMessageInChat.value;
  if (!message || !isMessageRestricted(message, resolvedInbox.value))
    return message;

  // ChatSPX (A4-5): o merge deixou só o cadeado. Sem o texto, o agente vê um 🔒 solto e não sabe
  // se a conversa está vazia ou restrita a outro agente. A chave já existe e está traduzida.
  return {
    ...message,
    content: `🔒 ${t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`,
    attachments: [],
    content_attributes: {},
    content_type: 'text',
  };
});

const voiceCallData = computed(() => {
  return {
    status: props.chat.additional_attributes?.call_status,
    direction: props.chat.additional_attributes?.call_direction,
  };
});

const isAIAssignee = computed(
  () =>
    resolvedAssignee.value?.type === 'agent_bot' ||
    chatMetadata.value.assignee_type === 'AgentBot'
);

const aiChipStyle = computed(() =>
  isAIAssignee.value && resolvedAssignee.value?.id
    ? aiAccentVars(resolvedAssignee.value.id)
    : {}
);

const isUnattendedAndMine = computed(() => {
  const waitingSince =
    props.chat.waiting_since ?? chatMetadata.value.waiting_since ?? 0;
  const assigneeId = resolvedAssignee.value?.id;

  return Boolean(
    Number(waitingSince) > 0 &&
      currentUser.value?.id &&
      assigneeId &&
      !isAIAssignee.value &&
      Number(assigneeId) === Number(currentUser.value.id)
  );
});

const showMetaSection = computed(
  () =>
    resolvedShowInboxName.value ||
    (props.showAssignee && resolvedAssignee.value.name) ||
    isAIAssignee.value ||
    props.chat.priority
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !resolvedContact.value?.blocked
);

const showLabelsSection = computed(
  () => props.chat.labels?.length > 0 || hasSlaPolicyId.value
);

const messagePreviewClass = computed(() => [
  hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
  !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
  props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
]);

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, resolvedInbox.value?.id);
  } else {
    emit('deSelectConversation', props.chat.id, resolvedInbox.value?.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: onSelectConversation,
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
</script>

<template>
  <div
    class="icon-animated relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 cursor-pointer conversation border-b border-n-slate-3 hover:border-n-surface-1 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      'active animate-card-select bg-n-background !border-n-surface-1':
        resolvedIsActiveChat,
      'selected bg-n-slate-2 !border-n-surface-1': selected,
      'px-0': compact,
      'px-3': !compact,
      'ltr:border-l-2 rtl:border-r-2 !border-n-amber-7 bg-n-amber-5/25 ring-1 ring-n-amber-6/50 ring-inset animate-sidebar-attention motion-reduce:animate-none':
        isUnattendedAndMine && !resolvedIsActiveChat && !selected,
      'ltr:border-l-2 rtl:border-r-2 !border-n-violet-7 bg-n-violet-3/40':
        isAIAssignee &&
        !resolvedIsActiveChat &&
        !selected &&
        !isUnattendedAndMine,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      class="relative"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="resolvedContact.name"
        :src="resolvedContact.thumbnail"
        :size="32"
        :status="resolvedContact.availability_status"
        :class="!resolvedShowInboxName ? 'mt-4' : 'mt-8'"
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{ 'ltr:ml-2 rtl:mr-2': !compact, 'mx-2': compact }"
      >
        <InboxName
          v-if="resolvedShowInboxName"
          :inbox="resolvedInbox"
          class="flex-1 min-w-0"
        />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{ 'flex-1 justify-between': !resolvedShowInboxName }"
        >
          <span
            v-if="isAIAssignee && resolvedAssignee.name"
            class="ai-chip inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-semibold leading-3 whitespace-nowrap bg-[var(--ai-bg)] text-[var(--ai-text)] dark:bg-[var(--ai-dark-bg)] dark:text-[var(--ai-dark-text)]"
            :style="aiChipStyle"
          >
            <Icon
              icon="i-lucide-sparkles"
              class="i-lucide-sparkles size-3 flex-shrink-0"
            />
            {{ resolvedAssignee.name }}
          </span>
          <span
            v-else-if="showAssignee && resolvedAssignee.name"
            class="conversation--assignee text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center gap-px truncate"
          >
            <Icon
              icon="i-lucide-user-round"
              class="i-lucide-user size-3 flex-shrink-0"
            />
            <span class="truncate">{{ resolvedAssignee.name }}</span>
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        v-if="resolvedContact"
        class="conversation--user text-sm my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="hasUnread ? 'font-semibold' : 'font-medium'"
      >
        {{ resolvedContact.name }}
      </h4>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        :message="previewMessage"
        default-empty-message=""
        class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm"
        :class="messagePreviewClass"
      />
      <p
        v-else
        class="text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
        :class="messagePreviewClass"
      >
        <Icon
          icon="i-lucide-info"
          class="size-4 -mt-0.5 align-middle inline-block"
        />
        <span class="mx-0.5">{{ $t('CHAT_LIST.NO_MESSAGES') }}</span>
      </p>
      <div
        class="absolute flex flex-col ltr:right-3 rtl:left-3"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <span class="ml-auto font-normal leading-4 text-xxs">
          <TimeAgo
            :last-activity-timestamp="
              chat.last_activity_at ||
              chat.updated_at ||
              chat.timestamp ||
              chat.created_at
            "
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="ltr:ml-auto rtl:mr-auto mt-1"
        />
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.ai-chip {
  position: relative;
  overflow: hidden;
}

.ai-chip::after {
  position: absolute;
  inset: 0;
  content: '';
  background: linear-gradient(
    105deg,
    transparent 35%,
    var(--ai-shimmer, rgba(255, 255, 255, 0.35)) 50%,
    transparent 65%
  );
  transform: translateX(-100%);
  animation: ai-chip-shimmer 3.5s ease-in-out infinite;
}

@keyframes ai-chip-shimmer {
  0%,
  70%,
  100% {
    transform: translateX(-100%);
  }
  85% {
    transform: translateX(100%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .ai-chip::after {
    animation: none;
  }
}
</style>
