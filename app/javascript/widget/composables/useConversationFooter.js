import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { sendEmailTranscript } from 'widget/api/conversation';
import { IFrameHelper } from 'widget/helpers/utils';
import { CHATWOOT_ON_START_CONVERSATION } from 'widget/constants/sdkEvents';

const TRANSCRIPT_COOLDOWN_MS = 15000;

/**
 * O comportamento do rodape da conversa — bloco 2.05.
 *
 * Sai de `ChatFooter.vue` porque o aceite 7 pede que aquele arquivo fique
 * abaixo de 60 linhas. Nada aqui e novo: e o mesmo codigo, no lugar onde da
 * para testa-lo sem montar a arvore de componentes inteira.
 */
export const useConversationFooter = () => {
  const store = useStore();
  const router = useRouter();
  const { t } = useI18n();

  const inReplyTo = ref(null);
  const isSendingTranscript = ref(false);
  const transcriptCooldown = ref(false);
  let cooldownTimer = null;

  const conversationAttributes = computed(
    () => store.getters['conversationAttributes/getConversationParams']
  );
  const currentUser = computed(() => store.getters['contacts/getCurrentUser']);

  const hasEmail = computed(() => Boolean(currentUser.value?.has_email));

  const hideReplyBox = computed(() => {
    const { allowMessagesAfterResolved } = window.chatwootWebChannel;
    return (
      !allowMessagesAfterResolved &&
      conversationAttributes.value.status === 'resolved'
    );
  });

  const hasReplyTo = computed(() =>
    Boolean(inReplyTo.value?.content || inReplyTo.value?.attachments)
  );

  const replyToId = () => inReplyTo.value?.id ?? null;

  const handleSendMessage = async content => {
    await store.dispatch('conversation/sendMessage', {
      content,
      replyTo: replyToId(),
    });
    inReplyTo.value = null;
    if (store.getters['conversation/getConversationSize'] === 0) {
      store.dispatch('conversationAttributes/getAttributes');
    }
  };

  const handleSendAttachment = async attachment => {
    await store.dispatch('conversation/sendAttachment', {
      attachment,
      replyTo: replyToId(),
    });
    inReplyTo.value = null;
  };

  const startNewConversation = () => {
    router.replace({ name: 'prechat-form' });
    IFrameHelper.sendMessage({
      event: 'onEvent',
      eventIdentifier: CHATWOOT_ON_START_CONVERSATION,
      data: { hasConversation: true },
    });
  };

  const sendTranscript = async () => {
    if (
      !hasEmail.value ||
      isSendingTranscript.value ||
      transcriptCooldown.value
    )
      return;

    isSendingTranscript.value = true;
    try {
      await sendEmailTranscript();
      transcriptCooldown.value = true;
      clearTimeout(cooldownTimer);
      cooldownTimer = setTimeout(() => {
        transcriptCooldown.value = false;
      }, TRANSCRIPT_COOLDOWN_MS);
      emitter.emit(BUS_EVENTS.SHOW_ALERT, {
        message: t('EMAIL_TRANSCRIPT.SEND_EMAIL_SUCCESS'),
        type: 'success',
      });
    } catch (error) {
      emitter.emit(BUS_EVENTS.SHOW_ALERT, {
        message: t('EMAIL_TRANSCRIPT.SEND_EMAIL_ERROR'),
      });
    } finally {
      isSendingTranscript.value = false;
    }
  };

  const toggleReplyTo = message => {
    inReplyTo.value = message;
  };

  onMounted(() =>
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, toggleReplyTo)
  );
  onBeforeUnmount(() => {
    emitter.off(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, toggleReplyTo);
    clearTimeout(cooldownTimer);
  });

  return {
    inReplyTo,
    hasReplyTo,
    hideReplyBox,
    hasEmail,
    isSendingTranscript,
    transcriptCooldown,
    isWidgetStyleFlat: computed(
      () => store.getters['appConfig/isWidgetStyleFlat']
    ),
    handleSendMessage,
    handleSendAttachment,
    startNewConversation,
    sendTranscript,
  };
};
