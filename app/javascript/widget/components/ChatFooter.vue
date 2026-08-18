<script setup>
// CASCA (bloco 2.05). O comportamento — envio, anexo, transcricao por e-mail,
// nova conversa e a mensagem citada — mora em `useConversationFooter`. Aqui fica
// so a decisao de o que mostrar.
import CustomButton from 'shared/components/Button.vue';
import FooterReplyTo from 'widget/components/FooterReplyTo.vue';
import ChatInputWrap from 'widget/components/ChatInputWrap.vue';
import { useConversationFooter } from '../composables/useConversationFooter';

const f = useConversationFooter();
</script>

<template>
  <footer
    v-if="!f.hideReplyBox.value"
    class="relative z-50 mb-1"
    :class="{
      'rounded-lg': !f.isWidgetStyleFlat.value,
      'pt-2.5 shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.05)] dark:shadow-[0px_-20px_20px_1px_rgba(0,_0,_0,_0.15)] rounded-t-none':
        f.hasReplyTo.value,
    }"
  >
    <FooterReplyTo
      v-if="f.hasReplyTo.value"
      :in-reply-to="f.inReplyTo.value"
      @dismiss="f.inReplyTo.value = null"
    />
    <ChatInputWrap
      class="shadow-sm"
      :on-send-message="f.handleSendMessage"
      :on-send-attachment="f.handleSendAttachment"
    />
  </footer>
  <div v-else>
    <CustomButton class="font-medium" block @click="f.startNewConversation">
      {{ $t('START_NEW_CONVERSATION') }}
    </CustomButton>
    <CustomButton
      v-if="f.hasEmail.value"
      type="clear"
      class="font-normal"
      :disabled="f.isSendingTranscript.value || f.transcriptCooldown.value"
      @click="f.sendTranscript"
    >
      {{ $t('EMAIL_TRANSCRIPT.BUTTON_TEXT') }}
    </CustomButton>
  </div>
</template>
