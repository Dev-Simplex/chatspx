<script>
import ChatMessage from 'widget/components/ChatMessage.vue';
import AgentTypingBubble from 'widget/components/AgentTypingBubble.vue';
import DateSeparator from 'shared/components/DateSeparator.vue';
import Spinner from 'shared/components/Spinner.vue';
import { useDarkMode } from 'widget/composables/useDarkMode';
import { calcularAgrupamento } from 'widget/composables/useMessageGrouping';
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
    // ── Bloco 2.02/2.03 — o agrupamento, calculado POR BLOCO DE DATA ─────────
    //
    // Este recorte não é detalhe: era o que o seletor de irmão adjacente fazia
    // sem dizer. Cada bloco de data é uma `<div class="messages-wrap">`
    // própria, então a primeira linha de um dia NUNCA teve irmão anterior — e
    // portanto nunca continuou o grupo do dia anterior. Rodar
    // `calcularAgrupamento` na conversa achatada mudaria justamente essa linha,
    // que é a mais visível da lista.
    agrupamentoPorBloco() {
      return this.groupedMessages.map(bloco =>
        calcularAgrupamento(bloco.messages)
      );
    },
    // ── Bloco 2.12 — a terceira chave do `v-memo` ─────────────────────────────
    // As duas primeiras (a mensagem e a classe de agrupamento) cobrem o que
    // muda a linha. Esta cobre o que muda o TEXTO da linha sem mudar a
    // mensagem: o visitante trocando de idioma numa inbox com mais de um
    // habilitado. Sem ela, `RETRY`, `DOWNLOAD` e os rótulos de anexo ficariam
    // no idioma antigo até a mensagem se mexer — que pode ser nunca.
    idiomaAtual() {
      return this.$root.$i18n?.locale;
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
    // Três estados, não dois — e o terceiro é o que o `+` fazia por omissão.
    // A primeira linha de cada bloco de data não recebe classe nenhuma, porque
    // não havia irmão anterior com quem casar e portanto nenhuma das seis
    // regras se aplicava a ela.
    classeAgrupamento(indiceBloco, mensagem, indice) {
      const info = this.agrupamentoPorBloco[indiceBloco]?.[mensagem.id];
      if (!info || indice === 0) return null;
      return info.continuaGrupo ? 'is-continuacao' : 'is-abertura';
    },
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
        v-for="(groupedMessage, indiceBloco) in groupedMessages"
        :key="groupedMessage.date"
        class="messages-wrap"
      >
        <DateSeparator :date="groupedMessage.date" />
        <!-- `v-memo` — bloco 2.12. Cada linha renderiza markdown, e sem memo
             toda mudança reativa fora dela (o agente começou a digitar, o
             tema mudou, a lista rolou) refaz o `md.render` de TODAS as bolhas
             para produzir o mesmo HTML.

             A identidade de `message` é chave legítima aqui, e é por um
             motivo que vale escrever: o getter `getGroupedConversation`
             reconstrói cada mensagem (`{ showAvatar, ...message }`) sempre que
             recomputa, então objeto igual significa "o store não mexeu nesta
             conversa". O que ele NÃO cobre está nas outras duas chaves. -->
        <!-- eslint-disable vue/valid-v-memo -- A regra guarda o caso
             real (`v-memo` num descendente de `v-for`, que o Vue ignora), mas
             ela rastreia só o `v-for` MAIS EXTERNO: `vForElement` só é
             atribuído quando ainda é nulo, e depois exige que o `v-memo` esteja
             nesse elemento. Com `v-for` aninhado — blocos de data por fora,
             linhas por dentro — o de dentro nunca passa, embora este seja o
             padrão documentado do Vue (`v-memo` no MESMO elemento do `v-for`).
             Que ele funciona de fato está medido em
             `specs/memoDaLinha.spec.js`, não afirmado aqui. -->
        <ChatMessage
          v-for="(message, indice) in groupedMessage.messages"
          :key="message.id"
          v-memo="[
            message,
            classeAgrupamento(indiceBloco, message, indice),
            idiomaAtual,
          ]"
          :message="message"
          :classe-agrupamento="classeAgrupamento(indiceBloco, message, indice)"
        />
        <!-- eslint-enable vue/valid-v-memo -->
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
