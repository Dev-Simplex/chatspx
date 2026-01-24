<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useRouter } from 'vue-router';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const router = useRouter();

    // Navegar de volta ao dashboard ao pressionar ESC dentro de uma conversa
    const keyboardEvents = {
      Escape: {
        action: (e) => {
          // Prevenir o comportamento padrão do ESC
          e.preventDefault();
          e.stopPropagation();
          // Navegar de volta ao dashboard
          if (accountId.value) {
            router.push(`/app/accounts/${accountId.value}/dashboard`);
          }
        },
        allowOnFocusedInput: false,
      },
    };

    useKeyboardEvents(keyboardEvents);

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
      showPermissionModal: false,
      permissionErrorMessage: '',
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    async fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        try {
          await this.$store.dispatch('getConversation', this.conversationId);
        } catch (error) {
          if (error.response && error.response.status === 403) {
            this.permissionErrorMessage = 'Você não tem permissão para acessar esta conversa.';
            this.showPermissionModal = true;
          } else {
            this.permissionErrorMessage = 'Erro ao carregar a conversa.';
            this.showPermissionModal = true;
          }
        }
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0">
    <ChatList
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />
    <ConversationBox
      v-if="showMessageView"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
    <div v-if="showPermissionModal" class="modal-overlay">
      <div class="modal-content">
        <h2>Atenção</h2>
        <p>{{ permissionErrorMessage }}</p>
        <button
          @click="() => {
            this.showPermissionModal = false;
            this.$router.push(
              `/app/accounts/${this.accountId}/conversations`
            );
          }"
        >
          Voltar para conversas
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(30, 30, 30, 0.95); /* cinza escuro */
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}
.modal-content {
  background: #333;
  padding: 2rem 3rem;
  border-radius: 12px;
  box-shadow: 0 2px 16px rgba(0, 0, 0, 0.3);
  text-align: center;
}
.modal-content h2 {
  color: #e53935; /* vermelho */
  margin-bottom: 1rem;
  font-size: 2rem;
  font-weight: bold;
}
.modal-content p {
  color: #fff;
  font-size: 1.2rem;
  margin-bottom: 2rem;
}
button {
  margin-top: 1.5rem;
  padding: 0.7rem 2rem;
  background: #1976d2;
  color: #fff;
  border: none;
  border-radius: 5px;
  font-size: 1rem;
  cursor: pointer;
  transition: background 0.2s;
}
button:hover {
  background: #125ea6;
}
</style>
