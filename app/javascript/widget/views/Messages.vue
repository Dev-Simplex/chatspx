<script>
import { mapGetters } from 'vuex';

import ChatFooter from '../components/ChatFooter.vue';
import ConversationWrap from '../components/ConversationWrap.vue';

export default {
  components: { ChatFooter, ConversationWrap },
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
    <div class="flex flex-1 overflow-auto">
      <ConversationWrap :grouped-messages="groupedMessages" />
    </div>
    <ChatFooter class="px-5" />
  </div>
</template>
