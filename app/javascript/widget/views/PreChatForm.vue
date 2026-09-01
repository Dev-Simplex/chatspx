<script>
import { mapActions } from 'vuex';
import { useRouter } from 'vue-router';
import PreChatForm from '../components/PreChat/Form.vue';
import configMixin from '../mixins/configMixin';
import { ON_CONVERSATION_CREATED } from '../constants/widgetBusEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    PreChatForm,
  },
  mixins: [configMixin],
  setup() {
    const router = useRouter();
    return { router };
  },
  mounted() {
    // Register event listener for conversation creation
    emitter.on(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  beforeUnmount() {
    emitter.off(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  methods: {
    ...mapActions('conversation', ['clearConversations']),
    ...mapActions('conversationAttributes', ['clearConversationAttributes']),
    handleConversationCreated() {
      // Redirect to messages page after conversation is created
      this.router.replace({ name: 'messages' });
      // Only after successful navigation, reset the isUpdatingRoute UIflag in app/javascript/widget/router.js
      // See issue: https://github.com/chatwoot/chatwoot/issues/10736
    },

    onSubmit({
      fullName,
      emailAddress,
      message,
      activeCampaignId,
      phoneNumber,
      contactCustomAttributes,
      conversationCustomAttributes,
    }) {
      // Bloco 5.08 — a origem que o coletor guardou ANTES de existir conversa.
      //
      // `conversation/setCustomAttributes` guarda em `pendingCustomAttributes`
      // enquanto nao ha conversa, e `sendMessage` os leva junto da primeira
      // mensagem. Com pre-chat a conversa nasce por AQUI, e este caminho
      // montava o payload a mao: os `last_utm_source`/`gclid` do visitante que
      // veio de anuncio morriam em silencio, e nao havia depois — o
      // `messages_controller` so aplica `custom_attributes` quando cria a
      // conversa junto da mensagem.
      //
      // A LEITURA VEM ANTES DO `clearConversations()`: a mutation por tras dele
      // zera `pendingCustomAttributes`. Ler depois devolveria `{}` sempre, e o
      // conserto seria invisivel.
      //
      // O que o visitante DIGITOU vence a origem na colisao de chave: e o dado
      // mais recente e o mais verdadeiro.
      const origemPendente =
        this.$store.getters['conversation/getPendingCustomAttributes'] || {};
      const customAttributes = {
        ...origemPendente,
        ...(conversationCustomAttributes || {}),
      };

      // Contact custom attributes are sent within the same request that
      // identifies the contact. A separate update call would race the contact
      // merge on the server (matching email/phone) and write the values to
      // the destroyed contact, silently losing them.
      if (activeCampaignId) {
        emitter.emit('execute-campaign', {
          campaignId: activeCampaignId,
          customAttributes,
        });
        this.$store.dispatch('contacts/update', {
          user: {
            email: emailAddress,
            name: fullName,
            phone_number: phoneNumber,
            custom_attributes: contactCustomAttributes,
          },
        });
      } else {
        this.clearConversations();
        this.clearConversationAttributes();
        this.$store.dispatch('conversation/createConversation', {
          fullName: fullName,
          emailAddress: emailAddress,
          message: message,
          phoneNumber: phoneNumber,
          customAttributes: customAttributes,
          contactCustomAttributes: contactCustomAttributes,
        });
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-1 overflow-auto">
    <PreChatForm :options="preChatFormOptions" @submit-pre-chat="onSubmit" />
  </div>
</template>
