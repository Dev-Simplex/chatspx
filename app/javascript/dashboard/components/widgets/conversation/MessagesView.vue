<script>
import { ref, provide, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
// composable
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useLabelSuggestions } from 'dashboard/composables/useLabelSuggestions';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import ForwardMessageModal from 'next/message/ForwardMessageModal.vue';
import ConversationLabelSuggestion from './conversation/LabelSuggestion.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TakeoverApprovalBanner from 'dashboard/components-next/Conversation/TakeoverApprovalBanner.vue';
import TypingIndicator from 'next/message/TypingIndicator.vue';
import { useAlert } from 'dashboard/composables';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';

// stores and apis
import { mapGetters } from 'vuex';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { getTypingUsersText } from '../../../helper/commons';
import { calculateScrollTop } from './helpers/scrollTopCalculationHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_POLICY } from 'shared/constants/links';
import wootConstants from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  components: {
    MessageList,
    ForwardMessageModal,
    ReplyBox,
    TakeoverApprovalBanner,
    Banner,
    ConversationLabelSuggestion,
    Spinner,
    TypingIndicator,
    ResizableEditorWrapper,
  },
  mixins: [inboxMixin],
  setup() {
    const isPopOutReplyBox = ref(false);
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);

    useKeyboardEvents({
      Escape: {
        action: () => {
          isPopOutReplyBox.value = false;
        },
      },
    });

    const {
      captainTasksEnabled,
      isLabelSuggestionFeatureEnabled,
      getLabelSuggestions,
    } = useLabelSuggestions();

    provide('contextMenuElementTarget', conversationPanelRef);

    return {
      isPopOutReplyBox,
      captainTasksEnabled,
      getLabelSuggestions,
      isLabelSuggestionFeatureEnabled,
      conversationPanelRef,
      resizableEditorWrapperRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      isLoadingNext: false,
      heightBeforeLoad: null,
      scrollTopBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      isProgrammaticScroll: false,
      messageSentSinceOpened: false,
      labelSuggestions: [],
      isDarkMode: false,
      themeObserver: null,
      forwardSelectionMode: false,
      forwardSelectedMessageIds: [],
      showForwardModal: false,
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      listLoadingStatus: 'getAllMessagesLoaded',
      currentAccountId: 'getCurrentAccountId',
      hasNewerMessages: 'getHasNewerMessages',
      pendingNewMessageCount: 'getPendingNewMessageCount',
    }),
    isOpen() {
      return this.currentChat?.status === wootConstants.STATUS_TYPE.OPEN;
    },
    // F5: conversa sendo atendida pela IA (espelho captain como dono) — a área de
    // resposta fica "esmaecida" (IA no controle); enviar abre o modal de assunção.
    aiHandlingAssignee() {
      const assignee = this.currentChat?.meta?.assignee;
      return assignee?.type === 'agent_bot' ? assignee : null;
    },
    isAIHandling() {
      return Boolean(this.aiHandlingAssignee);
    },
    shouldShowLabelSuggestions() {
      return (
        this.isOpen &&
        this.captainTasksEnabled &&
        this.isLabelSuggestionFeatureEnabled &&
        !this.messageSentSinceOpened
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    isWahaInbox() {
      return !!this.inbox?.waha_session_name;
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        return filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    forwardPrimaryMessage() {
      const messageId = this.forwardSelectedMessageIds[0];
      const messages = this.currentChat?.messages || [];
      const message = messages.find(msg => msg.id === messageId);
      return (
        message || {
          id: messageId,
          content: '',
          conversationId: this.currentChat?.id,
          attachments: [],
        }
      );
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious)
      );
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },
    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
  },

  watch: {
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      this.fetchAllAttachmentsFromCurrentChat();
      this.fetchSuggestions();
      this.messageSentSinceOpened = false;
      this.forwardSelectionMode = false;
      this.forwardSelectedMessageIds = [];
      this.showForwardModal = false;
      this.resetReplyEditorHeight();
    },
  },

  created() {
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    // when a message is sent we set the flag to true this hides the label suggestions,
    // until the chat is changed and the flag is reset in the watch for currentChat
    emitter.on(BUS_EVENTS.MESSAGE_SENT, this.onMessageSent);
  },

  mounted() {
    this.addScrollListener();
    this.fetchAllAttachmentsFromCurrentChat();
    this.fetchSuggestions();
    this.initializeThemeObserver();
  },

  unmounted() {
    this.removeBusListeners();
    this.removeScrollListener();
    this.removeThemeObserver();
  },

  methods: {
    openWhatsappTemplateFromBanner() {
      emitter.emit(BUS_EVENTS.OPEN_WHATSAPP_TEMPLATE_MODAL);
    },
    async fetchSuggestions() {
      // start empty, this ensures that the label suggestions are not shown
      this.labelSuggestions = [];

      if (this.isLabelSuggestionDismissed()) {
        return;
      }

      // Early exit if conversation already has labels - no need to suggest more
      const existingLabels = this.currentChat?.labels || [];
      if (existingLabels.length > 0) return;

      if (!this.captainTasksEnabled || !this.isLabelSuggestionFeatureEnabled) {
        return;
      }

      this.labelSuggestions = await this.getLabelSuggestions();

      // once the labels are fetched, we need to scroll to bottom
      // but we need to wait for the DOM to be updated
      // so we use the nextTick method
      this.$nextTick(() => {
        // this param is added to route, telling the UI to navigate to the message
        // it is triggered by the SCROLL_TO_MESSAGE method
        // see setActiveChat on ConversationView.vue for more info
        const { messageId } = this.$route.query;

        // only trigger the scroll to bottom if the user has not scrolled
        // and there's no active messageId that is selected in view
        if (!messageId && !this.hasUserScrolled) {
          this.scrollToBottom();
        }
      });
    },
    isLabelSuggestionDismissed() {
      return LocalStorage.getFlag(
        LOCAL_STORAGE_KEYS.DISMISSED_LABEL_SUGGESTIONS,
        this.currentAccountId,
        this.currentChat.id
      );
    },
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    onMessageSent() {
      this.messageSentSinceOpened = true;
    },
    removeBusListeners() {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
      emitter.off(BUS_EVENTS.MESSAGE_SENT, this.onMessageSent);
    },
    onScrollToMessage({ messageId = '' } = {}) {
      const scrollToElement = () => {
        const el = document.getElementById(`message${messageId}`);
        if (!el) return false;
        this.isProgrammaticScroll = true;
        el.scrollIntoView({ behavior: 'smooth' });
        el.classList.add('highlight-message');
        // Casado com a duração da animação .highlight-message (2.4s) para o
        // realce terminar suave em vez de ser cortado no meio do fade.
        setTimeout(() => el.classList.remove('highlight-message'), 2400);
        return true;
      };

      this.$nextTick(() => {
        if (scrollToElement()) {
          this.fetchPreviousMessages();
          this.makeMessagesRead();
          return;
        }
        if (!messageId || !this.currentChat?.id) {
          this.scrollToBottom();
          this.makeMessagesRead();
          return;
        }
        this.$store
          .dispatch('fetchPreviousMessages', {
            after: Number(messageId) - 1,
            conversationId: this.currentChat.id,
            includeMeta: true,
          })
          .then(() => {
            setTimeout(() => {
              scrollToElement();
              this.makeMessagesRead();
            }, 300);
          })
          .catch(() => {
            this.scrollToBottom();
            this.makeMessagesRead();
          });
      });
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
    },
    scrollToBottom() {
      this.isProgrammaticScroll = true;
      let relevantMessages = [];

      // label suggestions are not part of the messages list
      // so we need to handle them separately
      let labelSuggestions =
        this.conversationPanel.querySelector('.label-suggestion');

      // if there are unread messages, scroll to the first unread message
      if (this.unreadMessageCount > 0) {
        // capturing only the unread messages
        relevantMessages =
          this.conversationPanel.querySelectorAll('.message--unread');
      } else if (labelSuggestions) {
        // when scrolling to the bottom, the label suggestions is below the last message
        // so we scroll there if there are no unread messages
        // Unread messages always take the highest priority
        relevantMessages = [labelSuggestions];
      } else {
        // if there are no unread messages or label suggestion, scroll to the last message
        // capturing last message from the messages list
        relevantMessages = Array.from(
          this.conversationPanel.querySelectorAll('.message--read')
        ).slice(-1);
      }

      this.conversationPanel.scrollTop = calculateScrollTop(
        this.conversationPanel.scrollHeight,
        this.$el.scrollHeight,
        relevantMessages
      );
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          const heightDifference =
            this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    async fetchNextMessages() {
      if (this.isLoadingNext || !this.hasNewerMessages) return;

      const { messages } = this.currentChat;
      if (!messages.length) return;

      this.isLoadingNext = true;
      this.setScrollParams();
      try {
        await this.$store.dispatch('fetchNextMessages', {
          conversationId: this.currentChat.id,
          after: messages[messages.length - 1].id,
        });
        this.setScrollParams();
      } catch (error) {
        // Ignore Error
      } finally {
        this.isLoadingNext = false;
      }
    },

    async jumpToLatest() {
      this.isProgrammaticScroll = true;
      await this.$store.dispatch('jumpToLatest', this.currentChat.id);
      this.$nextTick(() => this.scrollToBottom());
    },

    handleScroll(e) {
      if (this.isProgrammaticScroll) {
        this.isProgrammaticScroll = false;
        this.hasUserScrolled = false;
      } else {
        this.hasUserScrolled = true;
      }
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);

      const { scrollTop, scrollHeight, clientHeight } = e.target;
      this.fetchPreviousMessages(scrollTop);

      const distanceFromBottom = scrollHeight - scrollTop - clientHeight;
      if (distanceFromBottom < 100 && this.hasNewerMessages) {
        this.fetchNextMessages();
      }
    },

    makeMessagesRead() {
      this.$store.dispatch('markMessagesRead', { id: this.currentChat.id });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    startForwardSelection({ messageId }) {
      if (!messageId) return;
      this.forwardSelectionMode = true;
      this.forwardSelectedMessageIds = [messageId];
      this.showForwardModal = false;
    },
    toggleForwardSelection(messageId) {
      if (!this.forwardSelectionMode || !messageId) return;
      const index = this.forwardSelectedMessageIds.indexOf(messageId);
      if (index > -1) {
        this.forwardSelectedMessageIds.splice(index, 1);
      } else {
        if (this.forwardSelectedMessageIds.length >= 20) {
          useAlert(this.$t('CONVERSATION.FORWARD.MAX_MESSAGES', { count: 20 }));
          return;
        }
        this.forwardSelectedMessageIds.push(messageId);
      }
    },
    openForwardModal() {
      if (!this.forwardSelectedMessageIds.length) {
        useAlert(this.$t('CONVERSATION.FORWARD.SELECT_MESSAGES'));
        return;
      }
      this.showForwardModal = true;
    },
    closeForwardModal() {
      this.showForwardModal = false;
    },
    handleForwarded() {
      this.showForwardModal = false;
      this.forwardSelectionMode = false;
      this.forwardSelectedMessageIds = [];
    },
    cancelForwardSelection() {
      this.forwardSelectionMode = false;
      this.forwardSelectedMessageIds = [];
      this.showForwardModal = false;
    },
    initializeThemeObserver() {
      this.isDarkMode = document.body.classList.contains('dark');
      this.themeObserver = new MutationObserver(() => {
        this.isDarkMode = document.body.classList.contains('dark');
      });
      this.themeObserver.observe(document.body, {
        attributes: true,
        attributeFilter: ['class'],
      });
    },
    removeThemeObserver() {
      if (this.themeObserver) {
        this.themeObserver.disconnect();
        this.themeObserver = null;
      }
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
  >
    <div ref="topBannerRef">
      <!-- D1: pedido de atendimento pendente para o dono da conversa. -->
      <TakeoverApprovalBanner />
      <Banner
        v-if="!currentChat.can_reply"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg relative z-10"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
        :has-action-button="isAWhatsAppChannel"
        :action-button-label="
          $t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.SEND_TEMPLATE_ACTION')
        "
        action-button-icon="i-ph-whatsapp-logo"
        @primary-action="openWhatsappTemplateFromBanner"
      />
      <Banner
        v-else-if="hasDuplicateInstagramInbox"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg relative z-10"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto overflow-x-hidden relative h-full m-0 pb-4"
      :class="{
        'conversation-panel-dark': isDarkMode,
        'conversation-panel-light': !isDarkMode,
      }"
      :current-user-id="currentUserId"
      :first-unread-id="unReadMessages[0]?.id"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :messages="getMessages"
      :is-waha-inbox="isWahaInbox"
      :is-forward-mode="forwardSelectionMode"
      :selected-message-ids="forwardSelectedMessageIds"
      @retry="handleMessageRetry"
      @forward="startForwardSelection"
      @toggle-forward-selection="toggleForwardSelection"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
      </template>
      <template #unreadBadge>
        <li
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ConversationLabelSuggestion
          v-if="shouldShowLabelSuggestions"
          :suggested-labels="labelSuggestions"
          :chat-labels="currentChat.labels"
          :conversation-id="currentChat.id"
        />
      </template>
    </MessageList>
    <div
      class="flex relative flex-col"
      :class="{
        'modal-mask': isPopOutReplyBox,
        'bg-n-surface-1': !isPopOutReplyBox,
        'ai-handling-composer': isAIHandling,
      }"
    >
      <!-- F5: a barra de IA "está atendendo" + CTA "Assumir" agora vive no
           ReplyBoxBanner (acima do composer); aqui mantemos só o esmaecido. -->
      <div
        v-if="isPopOutReplyBox"
        class="absolute inset-0 z-[5] bg-black/20"
        aria-hidden="true"
        @click="isPopOutReplyBox = false"
      />
      <div
        v-if="hasNewerMessages"
        class="absolute flex items-center justify-center w-full -top-10 z-10"
      >
        <button
          class="flex items-center gap-1.5 py-1.5 px-4 shadow-md rounded-full bg-n-brand hover:bg-n-brand text-white text-xs font-semibold cursor-pointer transition-colors"
          @click="jumpToLatest"
        >
          <span v-if="pendingNewMessageCount > 0">
            {{ pendingNewMessageCount }}
            {{
              pendingNewMessageCount === 1
                ? $t('CONVERSATION.UNREAD_MESSAGE')
                : $t('CONVERSATION.UNREAD_MESSAGES')
            }}
          </span>
          <span v-else>
            {{ $t('CONVERSATION.NEWEST_MESSAGE') }}
          </span>
          <i class="i-lucide-arrow-down size-3.5" />
        </button>
      </div>
      <div
        v-if="isAnyoneTyping"
        class="absolute flex items-center justify-center w-full h-0 -top-7 z-10"
      >
        <div
          class="flex items-center py-1.5 pr-4 pl-4 shadow-md rounded-full bg-n-background text-n-slate-11 text-xs font-semibold my-2.5"
        >
          <span class="mr-1">{{ typingUserNames }}</span>
          <TypingIndicator />
        </div>
      </div>
      <div
        v-if="forwardSelectionMode"
        class="mx-4 mb-2 p-3 rounded-xl bg-n-background border border-n-weak shadow-sm"
      >
        <div class="flex items-center justify-between gap-3">
          <span class="text-sm text-n-slate-11">
            {{
              $t('CONVERSATION.FORWARD.SELECTED_COUNT', {
                count: forwardSelectedMessageIds.length,
              })
            }}
          </span>
          <div class="flex gap-2">
            <button
              class="px-3 py-1.5 text-sm font-medium text-n-slate-12 border border-n-weak rounded-lg hover:bg-n-slate-3 transition-colors"
              @click="cancelForwardSelection"
            >
              {{ $t('CONVERSATION.FORWARD.CANCEL') }}
            </button>
            <button
              :disabled="forwardSelectedMessageIds.length === 0"
              class="px-3 py-1.5 text-sm font-medium text-white bg-n-brand rounded-lg hover:bg-n-brand disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              @click="openForwardModal"
            >
              {{ $t('CONVERSATION.FORWARD.FORWARD') }}
            </button>
          </div>
        </div>
      </div>
      <div
        v-if="isPopOutReplyBox"
        class="relative z-10 w-full flex justify-center items-start overflow-auto min-h-0"
      >
        <ReplyBox
          :pop-out-reply-box="isPopOutReplyBox"
          @update:pop-out-reply-box="isPopOutReplyBox = $event"
        />
      </div>
      <ResizableEditorWrapper
        v-else
        ref="resizableEditorWrapperRef"
        :container-height="Math.max(0, containerHeight - topBannerHeight)"
      >
        <ReplyBox @toggle-editor-size="toggleReplyEditorSize" />
      </ResizableEditorWrapper>
    </div>
    <ForwardMessageModal
      :show="showForwardModal"
      :message="forwardPrimaryMessage"
      :selected-message-ids="forwardSelectedMessageIds"
      @close="closeForwardModal"
      @forwarded="handleForwarded"
    />
  </div>
</template>

<style scoped lang="scss">
// F5: composer "esmaecido" quando a IA atende (sinal de "IA no controle").
// O reply box fica de-emphasizado e clareia ao focar/passar o mouse — enviar
// dispara o modal de assunção (D2). prefers-reduced-motion desliga o glow.
.ai-handling-composer {
  :deep(.reply-box) {
    opacity: 0.6;
    transition: opacity 0.2s ease;
  }

  &:focus-within :deep(.reply-box),
  :deep(.reply-box):hover {
    opacity: 0.9;
  }
}

.conversation-panel {
  position: relative;
  // Background colors/images are owned by the WA skin (_wa-skin.scss).
  // Keep structural rules only (stacking context for messages).
  background-size: auto, 400px;
  background-position:
    0 0,
    0 0;
  background-repeat: repeat, repeat;

  > * {
    position: relative;
    z-index: 2;
  }
}

.modal-mask {
  @apply fixed inset-0 min-h-screen flex flex-col justify-center items-center;

  // Quando a wa-composer-bar está em uso (WhatsApp), o pill já cuida do
  // próprio dimensionamento. As regras antigas com min-height 27.5rem
  // foram pensadas para o composer LEGACY de e-mail e quebram o pill.
  :deep(.reply-box:not(:has(.wa-composer-bar)) .ProseMirror-woot-style) {
    @apply max-h-[25rem] min-h-[12rem];
  }

  :deep(.reply-box) {
    @apply border border-n-weak max-w-[75rem] w-[95%] sm:w-[85%] md:w-[70%] max-h-[90vh] overflow-y-auto;

    &.is-private {
      @apply dark:border-n-amber-3/30 border-n-amber-12/5;
    }
  }

  // Reply-box com pill: tira borda extra do modal, deixa o pill arredondado
  // ser o destaque visual.
  :deep(.reply-box:has(.wa-composer-bar)) {
    border: none !important;
    overflow: visible !important;
  }

  :deep(
      .reply-box.reply-box--popout:not(:has(.wa-composer-bar)) .reply-box__top
    ) {
    min-height: 27.5rem !important;
  }

  :deep(
      .reply-box.reply-box--popout:not(:has(.wa-composer-bar))
        .reply-box__top
        .input
    ) {
    min-height: 27.5rem !important;
  }

  :deep(.emoji-dialog) {
    @apply absolute ltr:left-auto rtl:right-auto bottom-1;
  }
}

:deep(.highlight-message) {
  animation: message-highlight 2.4s ease-out;
}

@keyframes message-highlight {
  0%,
  30% {
    background-color: rgb(250 204 21 / 0.35);
    border-radius: 0.5rem;
    box-shadow: 0 0 0 2px rgb(250 204 21 / 0.5);
  }

  100% {
    background-color: transparent;
    box-shadow: 0 0 0 2px transparent;
  }
}

@media (prefers-reduced-motion: reduce) {
  :deep(.highlight-message) {
    animation-duration: 1.2s;
  }
}
</style>
