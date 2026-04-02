<script>
import { mapGetters } from 'vuex';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
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

    isUnattendedAndMine() {
      const waitingSince =
        this.chat.waiting_since ?? this.chatMetadata.waiting_since ?? 0;
      const isUnattended = Number(waitingSince) > 0;
      const assigneeId = this.assignee?.id ?? this.chatMetadata.assignee?.id;
      const isMine =
        this.currentUser?.id &&
        assigneeId &&
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
    class="flex items-start gap-3 px-3 py-2.5 cursor-pointer border-b border-n-weak/30 transition-colors duration-150 hover:bg-n-slate-3/50 dark:hover:bg-n-alpha-2 group conversation"
    :class="{
      'bg-n-selected dark:bg-n-selected ltr:border-l-2 rtl:border-r-2 border-l-n-brand border-r-n-brand':
        isActiveChat,
      'unread-chat': hasUnread,
      'has-inbox-name': showInboxName,
      'conversation-selected bg-n-slate-2 dark:bg-n-slate-3': selected,
      'px-0': compact,
    }"
    @click="onCardClick"
    @contextmenu="openContextMenu($event)"
  >
    <!-- Avatar area with checkbox on hover -->
    <div
      class="relative flex-shrink-0"
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
        size="40px"
      />
    </div>

    <!-- Content area -->
    <div class="flex flex-col flex-1 min-w-0 gap-0.5 relative">
      <!-- Botão de dropdown no hover -->
      <NextButton
        v-if="enableContextMenu"
        ref="dropdownButtonRef"
        ghost
        slate
        sm
        icon="i-lucide-chevron-down"
        class="absolute ltr:right-0 rtl:left-0 top-0 opacity-0 group-hover:opacity-100 transition-opacity duration-200 ease-in-out z-10"
        @click.stop="openHoverDropdown($event)"
      />

      <!-- Line 1: Name + Timestamp -->
      <div class="flex items-center justify-between gap-2">
        <h4
          v-if="currentContact"
          class="text-sm my-0 capitalize truncate text-n-slate-12"
          :class="hasUnread ? 'font-semibold' : 'font-medium'"
        >
          {{ currentContact.name }}
        </h4>
        <span class="flex-shrink-0 whitespace-nowrap text-xs text-n-slate-10">
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
      </div>

      <!-- Line 2: Message Preview + Unread Badge -->
      <div class="flex items-center justify-between gap-2">
        <div class="flex-1 min-w-0">
          <InboxName v-if="showInboxName" :inbox="inbox" class="mb-0.5" />
          <VoiceCallStatus
            v-if="voiceCallData.status"
            key="voice-status-row"
            :status="voiceCallData.status"
            :direction="voiceCallData.direction"
            :message-preview-class="messagePreviewClass"
          />
          <MessagePreview
            v-else-if="lastMessageInChat"
            :message="lastMessageInChat"
            default-empty-message=""
            class="text-sm truncate leading-5"
            :class="
              hasUnread ? 'font-medium text-n-slate-12' : 'text-n-slate-11'
            "
          />
          <p
            v-else
            class="text-sm text-n-slate-11 truncate leading-5 my-0"
          >
            <fluent-icon
              size="16"
              class="-mt-0.5 align-middle inline-block text-n-slate-10"
              icon="info"
            />
            <span>
              {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
            </span>
          </p>
        </div>
        <span
          v-if="hasUnread"
          class="inline-flex items-center justify-center flex-shrink-0 rounded-full min-w-[20px] h-5 px-1.5 text-xs font-medium text-white bg-n-brand"
        >
          {{ unreadCount > 9 ? '9+' : unreadCount }}
        </span>
      </div>

      <!-- Line 3 (optional): Metadata - Labels + Priority + SLA + Assignee -->
      <div
        v-if="
          chat.labels?.length ||
          hasSlaPolicyId ||
          chat.priority ||
          (showAssignee && assignee.name)
        "
        class="flex items-center gap-1.5 mt-0.5"
      >
        <PriorityMark :priority="chat.priority" />
        <SLACardLabel
          v-if="hasSlaPolicyId"
          :chat="chat"
          class="flex-shrink-0"
        />
        <CardLabels
          :conversation-labels="chat.labels"
          class="flex-1 min-w-0"
        />
        <span
          v-if="showAssignee && assignee.name"
          class="flex-shrink-0 text-xs text-n-slate-11 truncate max-w-[80px]"
        >
          <fluent-icon icon="person" size="12" class="text-n-slate-11" />
          {{ assignee.name }}
        </span>
      </div>
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
.conversation {
  .checkbox-wrapper {
    @apply flex items-center justify-center rounded-full cursor-pointer;

    input[type='checkbox'] {
      @apply m-0 cursor-pointer accent-[#2dc46f];
    }
  }
}
</style>
