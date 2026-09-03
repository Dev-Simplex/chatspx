<script>
import TeamAvailability from 'widget/components/TeamAvailability.vue';
import { mapGetters } from 'vuex';
import { useRouter } from 'vue-router';
import configMixin from 'widget/mixins/configMixin';
import ArticleContainer from '../components/pageComponents/Home/Article/ArticleContainer.vue';
export default {
  name: 'Home',
  components: {
    ArticleContainer,
    TeamAvailability,
  },
  mixins: [configMixin],
  setup() {
    const router = useRouter();
    return { router };
  },
  computed: {
    ...mapGetters({
      availableAgents: 'agent/availableAgents',
      conversationSize: 'conversation/getConversationSize',
      unreadMessageCount: 'conversation/getUnreadMessageCount',
    }),
  },
  methods: {
    startConversation() {
      if (this.preChatFormEnabled && !this.conversationSize) {
        return this.router.replace({ name: 'prechat-form' });
      }
      return this.router.replace({ name: 'messages' });
    },
  },
};
</script>

<template>
  <div
    class="z-50 flex flex-col justify-end flex-1 w-full p-4 gap-4"
    :data-home-layout="profileConfig.homeLayout"
  >
    <TeamAvailability
      :available-agents="availableAgents"
      :has-conversation="!!conversationSize"
      :unread-count="unreadMessageCount"
      @start-conversation="startConversation"
    />

    <!--
      Bloco 3.17 — a base de conhecimento é governada por `showKnowledgeBase`
      (flag plana da §B.3), nunca pelo nome do perfil.

      O `v-if` faz o componente não MONTAR, e é isso que satisfaz o aceite: o
      `fetch` vive no `onMounted` do container, então esconder por CSS deixaria a
      requisição a `/articles` sair mesmo com a base desligada. `ArticleContainer`
      guarda a mesma regra por dentro, para o caso de ser montado de outro lugar.
    -->
    <ArticleContainer v-if="showKnowledgeBase" />
  </div>
</template>
