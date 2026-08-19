<script>
import { mapActions, mapGetters } from 'vuex';
import CustomButton from 'shared/components/Button.vue';
import FooterReplyTo from 'widget/components/FooterReplyTo.vue';
import WhatsAppExit from 'widget/components/WhatsAppExit.vue';
import ChatInputWrap from 'widget/components/ChatInputWrap.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { sendEmailTranscript } from 'widget/api/conversation';
import { registrarConversaoDaAbordagem } from 'widget/api/approachEvent';
import { useRouter } from 'vue-router';
import { IFrameHelper } from '../helpers/utils';
import {
  CHATWOOT_MESSAGE_SENT,
  CHATWOOT_ON_START_CONVERSATION,
} from '../constants/sdkEvents';
import { emitter } from 'shared/helpers/mitt';

const TRANSCRIPT_COOLDOWN_MS = 15000;

export default {
  components: {
    ChatInputWrap,
    CustomButton,
    FooterReplyTo,
    WhatsAppExit,
  },
  setup() {
    const router = useRouter();
    return { router };
  },
  data() {
    return {
      inReplyTo: null,
      isSendingTranscript: false,
      transcriptCooldown: false,
      transcriptCooldownTimer: null,
    };
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      conversationSize: 'conversation/getConversationSize',
      currentUser: 'contacts/getCurrentUser',
      isWidgetStyleFlat: 'appConfig/isWidgetStyleFlat',
    }),
    hideReplyBox() {
      const { allowMessagesAfterResolved } = window.chatwootWebChannel;
      const { status } = this.conversationAttributes;
      return !allowMessagesAfterResolved && status === 'resolved';
    },
    showEmailTranscriptButton() {
      return this.hasEmail;
    },
    hasEmail() {
      return this.currentUser && this.currentUser.has_email;
    },
    hasReplyTo() {
      return (
        this.inReplyTo && (this.inReplyTo.content || this.inReplyTo.attachments)
      );
    },
  },
  mounted() {
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.toggleReplyTo);
  },
  beforeUnmount() {
    clearTimeout(this.transcriptCooldownTimer);
  },
  methods: {
    ...mapActions('conversation', ['sendMessage', 'sendAttachment']),
    ...mapActions('conversationAttributes', ['getAttributes']),
    async handleSendMessage(content) {
      await this.sendMessage({
        content,
        replyTo: this.inReplyTo ? this.inReplyTo.id : null,
      });
      // reset replyTo message after sending
      this.inReplyTo = null;
      // O visitante ENVIOU. E este o fato que o 4.19 chama de conversao — nao
      // "abriu o painel", nao "clicou em iniciar conversa" (esse ja tinha nome,
      // CHATWOOT_ON_START_CONVERSATION, e dispara antes de existir mensagem).
      this.avisarConversao();
      // Update conversation attributes on new conversation
      if (this.conversationSize === 0) {
        this.getAttributes();
      }
    },
    avisarConversao() {
      // Duas pontas, um fato: o host zera o contador de familiaridade (4.19) e o
      // registro server-side ganha a conversao com o nivel que a produziu (4.21).
      IFrameHelper.sendMessage({
        event: 'onEvent',
        eventIdentifier: CHATWOOT_MESSAGE_SENT,
        data: {},
      });
      registrarConversaoDaAbordagem();
    },
    async handleSendAttachment(attachment) {
      await this.sendAttachment({
        attachment,
        replyTo: this.inReplyTo ? this.inReplyTo.id : null,
      });
      this.inReplyTo = null;
    },
    startNewConversation() {
      this.router.replace({ name: 'prechat-form' });
      IFrameHelper.sendMessage({
        event: 'onEvent',
        eventIdentifier: CHATWOOT_ON_START_CONVERSATION,
        data: { hasConversation: true },
      });
    },
    toggleReplyTo(message) {
      this.inReplyTo = message;
    },
    startTranscriptCooldown() {
      this.transcriptCooldown = true;
      clearTimeout(this.transcriptCooldownTimer);
      this.transcriptCooldownTimer = setTimeout(() => {
        this.transcriptCooldown = false;
      }, TRANSCRIPT_COOLDOWN_MS);
    },
    async sendTranscript() {
      if (
        !this.hasEmail ||
        this.isSendingTranscript ||
        this.transcriptCooldown
      ) {
        return;
      }
      this.isSendingTranscript = true;
      try {
        await sendEmailTranscript();
        this.startTranscriptCooldown();
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_SUCCESS'),
          type: 'success',
        });
      } catch (error) {
        emitter.emit(BUS_EVENTS.SHOW_ALERT, {
          message: this.$t('EMAIL_TRANSCRIPT.SEND_EMAIL_ERROR'),
        });
      } finally {
        this.isSendingTranscript = false;
      }
    },
  },
};
</script>

<template>
  <footer
    v-if="!hideReplyBox"
    class="relative z-50 mb-1"
    :class="{
      'rounded-lg': !isWidgetStyleFlat,
      'pt-2.5 shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.05)] dark:shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.15)] rounded-t-none':
        hasReplyTo,
    }"
  >
    <FooterReplyTo
      v-if="hasReplyTo"
      :in-reply-to="inReplyTo"
      @dismiss="inReplyTo = null"
    />
    <ChatInputWrap
      class="shadow-sm"
      :on-send-message="handleSendMessage"
      :on-send-attachment="handleSendAttachment"
    />
  </footer>
  <div v-else>
    <!-- Bloco 4.08: a saida so existe no perfil de captura e so com destino
         configurado; o proprio componente decide, e sem os dois ele nao
         renderiza nada. -->
    <WhatsAppExit />
    <CustomButton class="font-medium" block @click="startNewConversation">
      {{ $t('START_NEW_CONVERSATION') }}
    </CustomButton>
    <CustomButton
      v-if="showEmailTranscriptButton"
      type="clear"
      class="font-normal"
      :disabled="isSendingTranscript || transcriptCooldown"
      @click="sendTranscript"
    >
      {{ $t('EMAIL_TRANSCRIPT.BUTTON_TEXT') }}
    </CustomButton>
  </div>
</template>
