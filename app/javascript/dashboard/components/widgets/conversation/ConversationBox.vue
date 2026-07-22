<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
// CopilotPanel.vue removido — CopilotContainer (Dashboard.vue) já renderiza
// o painel oficial Chatwoot. Manter os dois causava 2 painéis sobrepostos
// quando is_copilot_panel_open virava true.
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import ConversationAccessBlocked from './ConversationAccessBlocked.vue';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
    ConversationAccessBlocked,
  },
  props: {
    inboxId: {
      type: [Number, String],
      default: '',
      required: false,
    },
    isInboxView: {
      type: Boolean,
      default: false,
    },
    isContactPanelOpen: {
      type: Boolean,
      default: true,
    },
    isOnExpandedLayout: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return { activeIndex: 0 };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      dashboardApps: 'dashboardApps/getRecords',
      currentAccount: 'getCurrentAccount',
      accessBlockedMetaFor: 'getAccessBlockedMeta',
    }),
    // A conversa da rota — cobre os DOIS caminhos: já carregada na lista
    // (currentChat) ou aberta por link/busca antes de carregar (rota).
    blockedConversationId() {
      // o param da rota é snake_case (conversation_id)
      return (
        this.currentChat.id ||
        Number(this.$route.params.conversation_id) ||
        null
      );
    },
    // Isolamento de acesso: se a conversa aberta é de outro agente (403), mostra o
    // painel de bloqueio no lugar das mensagens / do empty-state.
    accessBlockedMeta() {
      return this.blockedConversationId
        ? this.accessBlockedMetaFor(this.blockedConversationId)
        : null;
    },
    chatWallpaperStyle() {
      const url = this.currentAccount?.settings?.chat_wallpaper_url;
      if (!url) return null;
      return {
        backgroundImage: `url('${url}')`,
        backgroundSize: 'cover',
        backgroundPosition: 'center',
      };
    },
    dashboardAppTabs() {
      return [
        {
          key: 'messages',
          index: 0,
          name: this.$t('CONVERSATION.DASHBOARD_APP_TAB_MESSAGES'),
        },
        ...this.dashboardApps.map((dashboardApp, index) => ({
          key: `dashboard-${dashboardApp.id}`,
          index: index + 1,
          name: dashboardApp.title,
        })),
      ];
    },
    showContactPanel() {
      return this.isContactPanelOpen && this.currentChat.id;
    },
  },
  watch: {
    'currentChat.inbox_id': {
      immediate: true,
      handler(inboxId) {
        if (inboxId) {
          this.$store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
        }
      },
    },
    'currentChat.id'() {
      this.fetchLabels();
      this.activeIndex = 0;
    },
  },
  mounted() {
    this.fetchLabels();
    this.$store.dispatch('dashboardApps/get');
  },
  methods: {
    fetchLabels() {
      if (!this.currentChat.id) {
        return;
      }
      this.$store.dispatch('conversationLabels/get', this.currentChat.id);
    },
    onDashboardAppTabChange(index) {
      this.activeIndex = index;
    },
  },
};
</script>

<template>
  <div
    class="conversation-details-wrap flex flex-col min-w-0 w-full bg-n-chat-bg relative"
    :class="{
      'border-l rtl:border-l-0 rtl:border-r border-n-weak': !isOnExpandedLayout,
    }"
    :style="chatWallpaperStyle"
  >
    <ConversationHeader
      v-if="currentChat.id"
      :chat="currentChat"
      :show-back-button="isOnExpandedLayout && !isInboxView"
      :show-icon-only="!isOnExpandedLayout"
      :class="{
        '!pt-0': !dashboardApps.length,
      }"
    />
    <woot-tabs
      v-if="dashboardApps.length && currentChat.id"
      :index="activeIndex"
      class="h-10"
      @change="onDashboardAppTabChange"
    >
      <woot-tabs-item
        v-for="tab in dashboardAppTabs"
        :key="tab.key"
        :index="tab.index"
        :name="tab.name"
        :show-badge="false"
        is-compact
      />
    </woot-tabs>
    <div v-show="!activeIndex" class="flex h-full min-h-0 m-0">
      <ConversationAccessBlocked
        v-if="accessBlockedMeta"
        :conversation-id="blockedConversationId"
        :meta="accessBlockedMeta"
      />
      <MessagesView
        v-else-if="currentChat.id"
        :inbox-id="inboxId"
        :is-inbox-view="isInboxView"
      />
      <EmptyState
        v-else-if="!isInboxView"
        :is-on-expanded-layout="isOnExpandedLayout"
      />
      <slot />
    </div>
    <DashboardAppFrame
      v-for="(dashboardApp, index) in dashboardApps"
      v-show="activeIndex - 1 === index"
      :key="currentChat.id + '-' + dashboardApp.id"
      :is-visible="activeIndex - 1 === index"
      :config="dashboardApps[index].content"
      :position="index"
      :current-chat="currentChat"
    />
  </div>
</template>
