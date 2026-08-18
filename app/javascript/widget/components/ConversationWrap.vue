<script>
import ChatMessage from 'widget/components/ChatMessage.vue';
import AgentTypingBubble from 'widget/components/AgentTypingBubble.vue';
import DateSeparator from 'shared/components/DateSeparator.vue';
import Spinner from 'shared/components/Spinner.vue';
import { useDarkMode } from 'widget/composables/useDarkMode';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { mapActions, mapGetters } from 'vuex';

export default {
  name: 'ConversationWrap',
  components: {
    ChatMessage,
    AgentTypingBubble,
    DateSeparator,
    Spinner,
  },
  props: {
    groupedMessages: {
      type: Array,
      default: () => [],
    },
  },
  setup() {
    const { darkMode, prefersDarkMode } = useDarkMode();
    return { darkMode, prefersDarkMode };
  },
  data() {
    return {
      previousScrollHeight: 0,
      previousConversationSize: 0,
    };
  },
  computed: {
    ...mapGetters({
      earliestMessage: 'conversation/getEarliestMessage',
      lastMessage: 'conversation/getLastMessage',
      allMessagesLoaded: 'conversation/getAllMessagesLoaded',
      isFetchingList: 'conversation/getIsFetchingList',
      conversationSize: 'conversation/getConversationSize',
      isAgentTyping: 'conversation/getIsAgentTyping',
      conversationAttributes: 'conversationAttributes/getConversationParams',
    }),
    // Bloco 2.10. Lia `darkMode` cru, então o valor `auto` — que agora é o
    // DEFAULT — caía sempre em `light-scheme`, mesmo com o sistema escuro e o
    // resto do painel já escuro. `prefersDarkMode` é o valor RESOLVIDO: é ele
    // que o `App.vue` usa para a classe `dark`, e as duas decisões precisam
    // sair da mesma fonte.
    colorSchemeClass() {
      return this.prefersDarkMode ? 'dark-scheme' : 'light-scheme';
    },
    showStatusIndicator() {
      const { status } = this.conversationAttributes;
      const isConversationInPendingStatus = status === 'pending';
      const isLastMessageIncoming =
        this.lastMessage.message_type === MESSAGE_TYPE.INCOMING;
      return (
        this.isAgentTyping ||
        (isConversationInPendingStatus && isLastMessageIncoming)
      );
    },
  },
  watch: {
    allMessagesLoaded() {
      this.previousScrollHeight = 0;
    },
  },
  mounted() {
    this.$el.addEventListener('scroll', this.handleScroll);
    this.scrollToBottom();
  },
  updated() {
    if (this.previousConversationSize !== this.conversationSize) {
      this.previousConversationSize = this.conversationSize;
      this.scrollToBottom();
    }
  },
  unmounted() {
    this.$el.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    ...mapActions('conversation', ['fetchOldConversations']),
    scrollToBottom() {
      const container = this.$el;
      container.scrollTop = container.scrollHeight - this.previousScrollHeight;
      this.previousScrollHeight = 0;
    },
    handleScroll() {
      if (
        this.isFetchingList ||
        this.allMessagesLoaded ||
        !this.conversationSize
      ) {
        return;
      }

      if (this.$el.scrollTop < 100) {
        this.fetchOldConversations({ before: this.earliestMessage.id });
        this.previousScrollHeight = this.$el.scrollHeight;
      }
    },
  },
};
</script>

<template>
  <div
    class="conversation--container"
    :class="[
      colorSchemeClass,
      prefersDarkMode
        ? 'conversation-container-dark'
        : 'conversation-container-light',
    ]"
  >
    <!-- `role="log"` marca a região onde chegam mensagens novas, e é o que faz
         o leitor de tela anunciar a resposta do agente sem o visitante ter de
         sair do campo de texto para procurá-la. O papel já implica
         `aria-live="polite"`, então não o repetimos: `polite` espera a pausa da
         fala em vez de interromper, que é o comportamento certo para chat.
         `aria-label` porque uma região precisa de nome para ser navegável. -->
    <div
      class="conversation-wrap"
      role="log"
      :aria-label="$t('A11Y.CONVERSATION_LOG')"
      :class="{ 'is-typing': isAgentTyping }"
    >
      <div v-if="isFetchingList" class="message--loader">
        <Spinner />
      </div>
      <div
        v-for="groupedMessage in groupedMessages"
        :key="groupedMessage.date"
        class="messages-wrap"
      >
        <DateSeparator :date="groupedMessage.date" />
        <ChatMessage
          v-for="message in groupedMessage.messages"
          :key="message.id"
          :message="message"
        />
      </div>
      <AgentTypingBubble v-if="showStatusIndicator" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.conversation--container {
  display: flex;
  flex-direction: column;
  flex: 1;
  overflow-y: auto;
  color-scheme: light dark;
  position: relative;
  background-image: linear-gradient(rgba(0, 0, 0, 0.85), rgba(0, 0, 0, 0.85)),
    url('/assets/images/chat-spx-background.png');
  background-size: auto, 400px;
  background-position:
    0 0,
    0 0;
  background-repeat: repeat, repeat;

  &.light-scheme {
    color-scheme: light;
  }

  &.dark-scheme {
    color-scheme: dark;
  }

  &.conversation-container-light {
    background-image: linear-gradient(
        rgba(255, 255, 255, 0.85),
        rgba(255, 255, 255, 0.85)
      ),
      url('/assets/images/chat-spx-background-light.png');
    background-size: auto, 400px;
    background-position:
      0 0,
      0 0;
    background-repeat: repeat, repeat;
  }

  > * {
    position: relative;
    z-index: 2;
  }
}

.conversation-wrap {
  flex: 1;
  @apply px-2 pt-8 pb-2;
}

.message--loader {
  text-align: center;
}
</style>
