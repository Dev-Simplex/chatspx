<script>
import { mapGetters } from 'vuex';

import ChatFooter from '../components/ChatFooter.vue';
import ConversationWrap from '../components/ConversationWrap.vue';
import ConnectionBanner from '../components/ConnectionBanner.vue';

export default {
  components: { ChatFooter, ConversationWrap, ConnectionBanner },
  computed: {
    ...mapGetters({
      groupedMessages: 'conversation/getGroupedConversation',
    }),
  },
  mounted() {
    this.$store.dispatch('conversation/setUserLastSeen');
  },
};
</script>

<template>
  <!-- `bg-n-chat-bg` SAIU — bloco 2.04. Era classe MORTA: `chat-bg` não existe
       no namespace `n:` de `theme/colors.js`, então o Tailwind nunca gerou
       regra para ela e o fundo real sempre veio de `ConversationWrap`. A
       variante escura ao lado (`dark:bg-n-solid-1`) fazia parecer que o par
       estava tratado, e escondia que metade dele não existia.
       Quem pinta o fundo agora é `--w-surface-sunken`, no lugar certo. -->
  <div class="flex flex-col flex-1 overflow-hidden rounded-b-lg">
    <!-- Bloco 2.07 — a faixa de conexão vive ACIMA da lista e FORA do composer.
         Aqui ela empurra a conversa para baixo em vez de cobrir o campo de
         texto: o aceite do bloco diz "composer utilizável", e um overlay sobre
         o rodapé seria a forma mais fácil de reprovar nisso sem perceber. -->
    <ConnectionBanner />
    <div class="flex flex-1 overflow-auto">
      <ConversationWrap :grouped-messages="groupedMessages" />
    </div>
    <ChatFooter class="px-5" />
  </div>
</template>
