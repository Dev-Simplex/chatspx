<script setup>
// CASCA (bloco 2.05). O comportamento — envio, anexo, transcricao por e-mail,
// nova conversa e a mensagem citada — mora em `useConversationFooter`. Aqui fica
// so a decisao de o que mostrar.
// 4.08: `WhatsAppExit` nos DOIS ramos. O `v-else` exige conversa resolvida E
// `allow_messages_after_resolved` desligado (default `true`): montar so ali
// deixava a saida inalcancavel na conversa comum, que e onde o plano a pede
// (22-plano §B.4). Quem decide se ela aparece e o componente. Ver o spec.
import CustomButton from 'shared/components/Button.vue';
import FooterReplyTo from 'widget/components/FooterReplyTo.vue';
import ChatInputWrap from 'widget/components/ChatInputWrap.vue';
import WhatsAppExit from 'widget/components/WhatsAppExit.vue';
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
    <!-- 4.08 — a saida no RODAPE, o fluxo normal da conversa. -->
    <WhatsAppExit class="mb-2" />
    <ChatInputWrap
      class="shadow-sm"
      :on-send-message="f.handleSendMessage"
      :on-send-attachment="f.handleSendAttachment"
    />
  </footer>
  <div v-else>
    <!-- 4.08 — o fim do fluxo. O componente decide se aparece. -->
    <WhatsAppExit />
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
