<script>
import { defineAsyncComponent, getCurrentInstance, ref } from 'vue';
import { mapActions } from 'vuex';
import { useRouter } from 'vue-router';
import configMixin from '../mixins/configMixin';
import { ON_CONVERSATION_CREATED } from '../constants/widgetBusEvents';
import { emitter } from 'shared/helpers/mitt';
import { garantirFormKit } from '../helpers/formkitLazy';

export default {
  components: {
    // Assincrono de proposito (bloco 2.18): `Form.vue` importa `@formkit/vue`,
    // e um import estatico aqui traria a biblioteca de volta para o chunk desta
    // rota antes de o plugin existir. Assim o modulo do formulario so e buscado
    // depois que `garantirFormKit` registrou o plugin na app.
    PreChatForm: defineAsyncComponent(
      () => import('../components/PreChat/Form.vue')
    ),
  },
  mixins: [configMixin],
  setup() {
    const router = useRouter();
    // O plugin do FormKit precisa estar na app ANTES do primeiro `<FormKit>`.
    // `app.use()` nao exige ser chamado antes de `mount()`; exige ser chamado
    // antes do render — e e o `v-if` abaixo que garante a ordem.
    const formKitPronto = ref(false);
    const app = getCurrentInstance().appContext.app;
    garantirFormKit(app).then(() => {
      formKitPronto.value = true;
    });
    return { router, formKitPronto };
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
      // Contact custom attributes are sent within the same request that
      // identifies the contact. A separate update call would race the contact
      // merge on the server (matching email/phone) and write the values to
      // the destroyed contact, silently losing them.
      if (activeCampaignId) {
        emitter.emit('execute-campaign', {
          campaignId: activeCampaignId,
          customAttributes: conversationCustomAttributes,
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
          customAttributes: conversationCustomAttributes,
          contactCustomAttributes: contactCustomAttributes,
        });
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-1 overflow-auto">
    <PreChatForm
      v-if="formKitPronto"
      :options="preChatFormOptions"
      @submit-pre-chat="onSubmit"
    />
  </div>
</template>
