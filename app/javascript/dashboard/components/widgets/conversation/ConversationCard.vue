<script>
import { mapGetters } from 'vuex';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import Thumbnail from '../Thumbnail.vue';
import MessagePreview from './MessagePreview.vue';
import router from '../../../routes';
import { frontendURL, conversationUrl } from '../../../helper/URLHelper';
import InboxName from '../InboxName.vue';
import inboxMixin from 'shared/mixins/inboxMixin';
import ConversationContextMenu from './contextMenu/Index.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import PriorityMark from './PriorityMark.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import { aiAccentVars } from 'dashboard/helper/aiAccent';

const hasValidContent = msg => {
  if (!msg) return false;
  const hasContent =
    msg.content != null && String(msg.content).trim().length > 0;
  const hasAttachments =
    Array.isArray(msg.attachments) && msg.attachments.length > 0;
  return hasContent || hasAttachments || msg.private === true;
};

export default {
  components: {
    CardLabels,
    InboxName,
    Thumbnail,
    ConversationContextMenu,
    TimeAgo,
    MessagePreview,
    PriorityMark,
    SLACardLabel,
    ContextMenu,
    NextButton,
    VoiceCallStatus,
  },
  mixins: [inboxMixin],
  props: {
    activeLabel: {
      type: String,
      default: '',
    },
    chat: {
      type: Object,
      default: () => {},
    },
    hideInboxName: {
      type: Boolean,
      default: false,
    },
    hideThumbnail: {
      type: Boolean,
      default: false,
    },
    teamId: {
      type: [String, Number],
      default: 0,
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
    showAssignee: {
      type: Boolean,
      default: false,
    },
    conversationType: {
      type: String,
      default: '',
    },
    conversationStatus: {
      type: String,
      default: '',
    },
    selected: {
      type: Boolean,
      default: false,
    },
    compact: {
      type: Boolean,
      default: false,
    },
    enableContextMenu: {
      type: Boolean,
      default: false,
    },
    allowedContextMenuOptions: {
      type: Array,
      default: () => [],
    },
  },
  emits: [
    'contextMenuToggle',
    'assignAgent',
    'assignLabel',
    'removeLabel',
    'assignTeam',
    'markAsUnread',
    'markAsRead',
    'assignPriority',
    'updateConversationStatus',
    'deleteConversation',
    'selectConversation', // eslint-disable-line vue/no-unused-emit-declarations -- used dynamically in onSelectConversation
    'deSelectConversation', // eslint-disable-line vue/no-unused-emit-declarations -- used dynamically in onSelectConversation
  ],
  setup() {
    // Isolamento por agente: mesma regra do thread (Message.vue), reusada p/ mascarar o
    // preview da lista quando a última msg é de outro agente (pode ter entrado via realtime).
    const { isMessageRestricted } = useAgentIsolation();
    return { isAgentMessageRestricted: isMessageRestricted };
  },
  data() {
    return {
      hovered: false,
      showContextMenu: false,
      contextMenu: {
        x: null,
        y: null,
      },
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      inboxesList: 'inboxes/getInboxes',
      activeInbox: 'getSelectedInbox',
      accountId: 'getCurrentAccountId',
      currentUser: 'getCurrentUser',
    }),
    chatMetadata() {
      return this.chat.meta || {};
    },

    assignee() {
      return this.chatMetadata.assignee || {};
    },

    isAIAssignee() {
      return this.assignee?.type === 'agent_bot';
    },

    // Quem pode marcar como lida EXPLICITAMENTE (o botão). Não confundir com o
    // gate de leitura implícita: abrir conversa que não é sua deixou de limpar o
    // "não lida" (ver `may_clear_unread_marker?`). O botão segue disponível em
    // conversa sem dono e da IA — é o único jeito de zerar essas — e em conversa
    // com dono humano só pra ele.
    canMarkAsRead() {
      const assigneeId = this.assignee?.id;
      if (!assigneeId || this.isAIAssignee) return true;
      return Number(assigneeId) === Number(this.currentUser?.id);
    },
    // Cor própria da IA (determinística por id do espelho) para o chip do card.
    aiChipStyle() {
      return this.isAIAssignee && this.assignee?.id
        ? aiAccentVars(this.assignee.id)
        : {};
    },

    isUnattendedAndMine() {
      const waitingSince =
        this.chat.waiting_since ?? this.chatMetadata.waiting_since ?? 0;
      const isUnattended = Number(waitingSince) > 0;
      const assigneeId = this.assignee?.id ?? this.chatMetadata.assignee?.id;
      const isMine =
        this.currentUser?.id &&
        assigneeId &&
        // Mesma proteção do getMineChats: um espelho captain com id colidindo
        // com o do usuário NÃO é "minha" — IA nunca conta como atribuída a mim.
        !this.isAIAssignee &&
        Number(assigneeId) === Number(this.currentUser.id);
      return Boolean(isUnattended && isMine);
    },

    voiceCallData() {
      return {
        status: this.chat.additional_attributes?.call_status,
        direction: this.chat.additional_attributes?.call_direction,
      };
    },

    currentContact() {
      const raw =
        this.chat.contact ||
        this.chatMetadata.contact ||
        this.chatMetadata.sender ||
        this.chat.sender ||
        this.chat.meta?.sender;
      if (!raw)
        return {
          name: 'Unknown',
          thumbnail: '',
          availability_status: 'offline',
          id: null,
        };

      const id = raw.id || null;
      const storeContact = id
        ? this.$store.getters['contacts/getContact'](id)
        : null;

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
          storeContact?.availability_status ||
          raw.availability_status ||
          'offline',
      };
    },

    isActiveChat() {
      return this.currentChat.id === this.chat.id;
    },

    unreadCount() {
      return this.chat.unread_count;
    },

    hasUnread() {
      return this.unreadCount > 0;
    },

    isPinned() {
      return Boolean(this.chat.pinned);
    },

    isInboxNameVisible() {
      return !this.activeInbox;
    },

    lastMessageInChat() {
      // Se tem array de mensagens, usar helper (como na lista normal)
      if (
        this.chat.messages &&
        Array.isArray(this.chat.messages) &&
        this.chat.messages.length > 0
      ) {
        const msg = getLastMessage(this.chat);
        if (msg) {
          return msg;
        }
      }

      // Prioridade 1: last_non_activity_message (mais importante, como na lista normal)
      if (this.chat.last_non_activity_message) {
        return this.chat.last_non_activity_message;
      }

      // Prioridade 2: meta.last_non_activity_message
      if (this.chatMetadata.last_non_activity_message) {
        return this.chatMetadata.last_non_activity_message;
      }

      // Prioridade 3: last_message (verificar se tem conteúdo válido)
      if (this.chat.last_message && hasValidContent(this.chat.last_message)) {
        return this.chat.last_message;
      }

      // Prioridade 4: meta.last_message
      if (
        this.chatMetadata.last_message &&
        hasValidContent(this.chatMetadata.last_message)
      ) {
        return this.chatMetadata.last_message;
      }

      // Prioridade 5: last_activity_message (fallback)
      if (
        this.chat.last_activity_message &&
        hasValidContent(this.chat.last_activity_message)
      ) {
        return this.chat.last_activity_message;
      }

      // Prioridade 6: meta.last_activity_message
      if (
        this.chatMetadata.last_activity_message &&
        hasValidContent(this.chatMetadata.last_activity_message)
      ) {
        return this.chatMetadata.last_activity_message;
      }

      // Se nada funcionar, retornar null (não mostrar "Nova Mensagem")
      return null;
    },

    inbox() {
      const { inbox_id: inboxId } = this.chat;
      const stateInbox = this.$store.getters['inboxes/getInbox'](inboxId);
      return stateInbox;
    },

    isLastMessageRestrictedByAgent() {
      // 3º argumento = a conversa: dela sai o time que isenta o supervisor
      // (sem supervisão o argumento é ignorado).
      return this.isAgentMessageRestricted(
        this.lastMessageInChat,
        this.inbox,
        this.chat
      );
    },

    // Mensagem a exibir no preview. Se restrita por agente, troca o conteúdo por 🔒 +
    // "Conteúdo restrito" e remove anexos/atributos, mantendo só quem enviou poder ver.
    previewMessage() {
      const msg = this.lastMessageInChat;
      if (!msg || !this.isLastMessageRestrictedByAgent) return msg;
      return {
        ...msg,
        content: `🔒 ${this.$t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`,
        attachments: [],
        content_attributes: {},
        content_type: 'text',
      };
    },

    showInboxName() {
      return (
        !this.hideInboxName &&
        this.isInboxNameVisible &&
        this.inboxesList.length > 1
      );
    },
    inboxName() {
      const stateInbox = this.inbox;
      return stateInbox.name || '';
    },
    hasSlaPolicyId() {
      return this.chat?.sla_policy_id;
    },
  },
  methods: {
    // Preferência individual: só mexe na lista de quem clicou.
    togglePin() {
      this.$store.dispatch('togglePin', { conversationId: this.chat.id });
    },

    onCardClick(e) {
      const { activeInbox, chat } = this;
      const path = frontendURL(
        conversationUrl({
          accountId: this.accountId,
          activeInbox,
          id: chat.id,
          label: this.activeLabel,
          teamId: this.teamId,
          foldersId: this.foldersId,
          conversationType: this.conversationType,
          conversationStatus: this.conversationStatus,
        })
      );

      if (e.metaKey || e.ctrlKey) {
        window.open(
          window.chatwootConfig.hostURL + path,
          '_blank',
          'noopener noreferrer nofollow'
        );
        return;
      }
      if (this.isActiveChat) {
        return;
      }

      router.push({ path });
    },
    onThumbnailHover() {
      this.hovered = !this.hideThumbnail;
    },
    onThumbnailLeave() {
      this.hovered = false;
    },
    onSelectConversation(checked) {
      const action = checked ? 'selectConversation' : 'deSelectConversation';
      this.$emit(action, this.chat.id, this.inbox.id);
    },
    openContextMenu(e) {
      if (!this.enableContextMenu) return;
      e.preventDefault();
      this.$emit('contextMenuToggle', true);
      this.contextMenu.x = e.pageX || e.clientX;
      this.contextMenu.y = e.pageY || e.clientY;
      this.showContextMenu = true;
    },
    openHoverDropdown(e) {
      if (!this.enableContextMenu) return;
      const buttonRef = this.$refs.dropdownButtonRef;
      if (!buttonRef) return;

      e.preventDefault();
      e.stopPropagation();

      this.$nextTick(() => {
        const buttonEl = buttonRef.$el || buttonRef;
        if (!buttonEl || !buttonEl.getBoundingClientRect) return;

        const rect = buttonEl.getBoundingClientRect();

        this.contextMenu.x = rect.right;
        this.contextMenu.y = rect.bottom + 4;

        this.showContextMenu = true;
        this.$emit('contextMenuToggle', true);
      });
    },
    closeContextMenu() {
      this.$emit('contextMenuToggle', false);
      this.showContextMenu = false;
      this.contextMenu.x = null;
      this.contextMenu.y = null;
    },
    onUpdateConversation(status, snoozedUntil) {
      this.closeContextMenu();
      this.$emit(
        'updateConversationStatus',
        this.chat.id,
        status,
        snoozedUntil
      );
    },
    async onAssignAgent(agent) {
      this.$emit('assignAgent', agent, [this.chat.id]);
      this.closeContextMenu();
    },
    async onAssignLabel(label) {
      this.$emit('assignLabel', [label.title], [this.chat.id]);
      this.closeContextMenu();
    },
    async onRemoveLabel(label) {
      this.$emit('removeLabel', [label.title], [this.chat.id]);
      this.closeContextMenu();
    },
    async onAssignTeam(team) {
      this.$emit('assignTeam', team, this.chat.id);
      this.closeContextMenu();
    },
    async markAsUnread() {
      this.$emit('markAsUnread', this.chat.id);
      this.closeContextMenu();
    },
    async markAsRead() {
      this.$emit('markAsRead', this.chat.id);
      this.closeContextMenu();
    },
    async assignPriority(priority) {
      this.$emit('assignPriority', priority, this.chat.id);
      this.closeContextMenu();
    },
    async deleteConversation() {
      this.$emit('deleteConversation', this.chat.id);
      this.closeContextMenu();
    },
  },
};
</script>

<template>
  <div
    class="icon-animated relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full px-3 py-0 border-t-0 border-b-0 border-l-2 border-r-0 border-transparent border-solid cursor-pointer conversation hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group"
    :class="{
      'active animate-card-select bg-n-alpha-1 dark:bg-n-alpha-3': isActiveChat,
      'unread-chat': hasUnread,
      'has-inbox-name': showInboxName,
      'conversation-selected': selected,
      'bg-n-slate-2': selected,
      'px-0': compact,
      'px-3': !compact,
      'ltr:border-l-2 rtl:border-r-2 border-n-amber-7 bg-n-amber-5/25 ring-1 ring-n-amber-6/50 ring-inset animate-sidebar-attention motion-reduce:animate-none':
        isUnattendedAndMine && !isActiveChat && !selected,
      'ltr:border-l-2 rtl:border-r-2 border-n-violet-7 bg-n-violet-3/40':
        isAIAssignee && !isActiveChat && !selected && !isUnattendedAndMine,
    }"
    @click="onCardClick"
    @contextmenu="openContextMenu($event)"
  >
    <div
      class="relative"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <label
        v-if="hovered || selected"
        class="checkbox-wrapper absolute inset-0 z-20 backdrop-blur-[2px]"
        @click.stop
      >
        <input
          :value="selected"
          :checked="selected"
          class="checkbox"
          type="checkbox"
          @change="onSelectConversation($event.target.checked)"
        />
      </label>
      <Thumbnail
        v-if="!hideThumbnail && currentContact"
        :src="currentContact.thumbnail"
        :badge="inboxBadge"
        :username="currentContact.name"
        :status="currentContact.availability_status"
        size="32px"
      />
    </div>
    <div class="px-0 py-3 flex-1 w-[calc(100%-40px)] relative">
      <!-- Botão de dropdown no hover -->
      <NextButton
        v-if="enableContextMenu"
        ref="dropdownButtonRef"
        ghost
        slate
        sm
        icon="i-lucide-chevron-down"
        class="absolute ltr:right-0 rtl:left-0 top-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200 ease-in-out z-10"
        @click.stop="openHoverDropdown($event)"
      />
      <div
        class="flex justify-between conversation-card--meta group-hover:ltr:pr-8 group-hover:rtl:pl-8 transition-all duration-200"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" />
        <div class="flex gap-2 ml-2 rtl:mr-2 rtl:ml-0">
          <!-- IA: chip único com a cor própria da IA + shimmer (a entidade já diz
               que é IA pelo ícone; sem badge "IA" redundante ao lado). -->
          <span
            v-if="isAIAssignee && assignee.name"
            class="ai-chip inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-semibold leading-3 whitespace-nowrap bg-[var(--ai-bg)] text-[var(--ai-text)] dark:bg-[var(--ai-dark-bg)] dark:text-[var(--ai-dark-text)]"
            :style="aiChipStyle"
          >
            <span class="i-lucide-sparkles size-3 flex-shrink-0" />
            {{ assignee.name }}
          </span>
          <span
            v-else-if="showAssignee && assignee.name"
            class="conversation--assignee text-xs font-medium leading-3 py-0.5 px-0 inline-flex text-ellipsis overflow-hidden whitespace-nowrap"
          >
            <span class="i-lucide-user size-3" />
            {{ assignee.name }}
          </span>
          <PriorityMark :priority="chat.priority" />
        </div>
      </div>
      <h4
        v-if="currentContact"
        class="conversation--user text-n-slate-12 my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap group-hover:ltr:pr-8 group-hover:rtl:pl-8 transition-all duration-200 w-[calc(100%-140px)] font-normal"
      >
        {{ currentContact.name }}
      </h4>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        key="voice-status-row"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-if="lastMessageInChat"
        :message="previewMessage"
        default-empty-message=""
        class="conversation--message text-n-slate-11 my-0 mx-2 leading-6 h-6 text-sm overflow-hidden text-ellipsis whitespace-nowrap group-hover:ltr:pr-8 group-hover:rtl:pl-8 transition-all duration-200 max-w-[96%] w-[16.875rem]"
        :class="hasUnread ? 'conversation--message-unread font-medium' : ''"
      />
      <p
        v-else
        class="conversation--message text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 overflow-hidden text-ellipsis whitespace-nowrap group-hover:ltr:pr-8 group-hover:rtl:pl-8 transition-all duration-200 max-w-[96%] w-[16.875rem]"
        :class="hasUnread ? 'conversation--message-unread font-medium' : ''"
      >
        <span class="i-lucide-info size-4 -mt-0.5 align-middle inline-block" />
        <span>
          {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
        </span>
      </p>
      <div
        class="absolute flex flex-col mt-4 ltr:right-4 rtl:left-4 top-4 group-hover:ltr:right-10 group-hover:rtl:left-10 transition-all duration-200"
      >
        <!-- Alfinete: sempre visível quando fixada; no toque também, porque lá
             não existe hover (por isso o md: nas classes de opacidade). -->
        <button
          type="button"
          class="ltr:ml-auto rtl:mr-auto mb-0.5 flex size-4 items-center justify-center rounded transition-opacity"
          :class="
            isPinned
              ? 'text-n-brand'
              : 'text-n-slate-10 md:opacity-0 md:group-hover:opacity-100 hover:text-n-slate-12'
          "
          :title="
            isPinned
              ? $t('CHAT_LIST.UNPIN_CONVERSATION')
              : $t('CHAT_LIST.PIN_CONVERSATION')
          "
          @click.stop="togglePin"
        >
          <span class="i-lucide-pin size-3.5" />
        </button>
        <span class="conversation--timestamp ml-auto font-normal leading-4">
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
        <span
          class="unread shadow-lg rounded-full hidden text-xxs font-semibold h-4 leading-4 ltr:ml-auto rtl:mr-auto mt-1 min-w-[1rem] px-1 py-0 text-center text-white bg-n-teal-9"
        >
          {{ unreadCount > 9 ? '9+' : unreadCount }}
        </span>
      </div>
      <CardLabels :conversation-labels="chat.labels" class="mt-0.5 mx-2 mb-0">
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
    <ContextMenu
      v-if="showContextMenu"
      :x="contextMenu.x"
      :y="contextMenu.y"
      @close="closeContextMenu"
    >
      <ConversationContextMenu
        :status="chat.status"
        :inbox-id="inbox.id"
        :priority="chat.priority"
        :chat-id="chat.id"
        :has-unread-messages="hasUnread"
        :can-mark-as-read="canMarkAsRead"
        :conversation-labels="chat.labels"
        :allowed-options="allowedContextMenuOptions"
        @update-conversation="onUpdateConversation"
        @assign-agent="onAssignAgent"
        @assign-label="onAssignLabel"
        @remove-label="onRemoveLabel"
        @assign-team="onAssignTeam"
        @mark-as-unread="markAsUnread"
        @mark-as-read="markAsRead"
        @assign-priority="assignPriority"
        @delete-conversation="deleteConversation"
      />
    </ContextMenu>
  </div>
</template>

<style lang="scss" scoped>
// Badge "IA": shimmer sutil de luz iris passando — sinal de "IA ativa".
// Tokens only (light+dark via --iris-*). Respeita prefers-reduced-motion.
.ai-chip {
  position: relative;
  overflow: hidden;
}
.ai-chip::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 30%,
    rgb(var(--violet-11) / 0.18) 50%,
    transparent 70%
  );
  transform: translateX(-100%);
  animation: ai-badge-shimmer 2.8s ease-in-out infinite;
}
@keyframes ai-badge-shimmer {
  0% {
    transform: translateX(-100%);
  }
  60%,
  100% {
    transform: translateX(100%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-chip::after {
    animation: none;
    display: none;
  }
}

.conversation {
  &.unread-chat {
    .unread {
      @apply block;
    }
  }

  &.compact {
    @apply pl-0;

    .conversation-card--meta {
      @apply ltr:pr-4 rtl:pl-4;
    }

    .conversation--details {
      @apply rounded-sm ml-0 pl-5 pr-2;
    }
  }

  :deep(.user-thumbnail-box) {
    @apply mt-4;
  }

  &.conversation-selected {
    @apply bg-n-slate-2 dark:bg-n-slate-3;
  }

  &.has-inbox-name {
    :deep(.user-thumbnail-box) {
      @apply mt-8;
    }

    .checkbox-wrapper {
      @apply mt-8;
    }

    .conversation--meta {
      @apply mt-4;
    }
  }

  .checkbox-wrapper {
    @apply flex items-center justify-center rounded-full cursor-pointer mt-4;

    input[type='checkbox'] {
      @apply m-0 cursor-pointer accent-[#00a884];
    }
  }
}
</style>
