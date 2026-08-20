<script>
import { resolveMessageType, CitationList } from 'widget/message-types';

export default {
  name: 'AgentMessageBubble',
  components: { CitationList },
  // O call-site ainda passa `message-type`, que nenhum tipo consome (o
  // computed `isTemplate` que a lia nunca foi usado no template). Sem isto
  // ele desceria para o DOM como atributo solto.
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
    contentType: { type: String, default: null },
    messageId: { type: Number, default: null },
    messageContentAttributes: {
      type: Object,
      default: () => {},
    },
  },
  computed: {
    contentComponent() {
      return resolveMessageType(this.contentType);
    },
    // 6.03: as fontes que a resposta usou, quando o servidor as gravou. Rodapé da
    // bolha, e não parte do tipo — qualquer `content_type` pode citar.
    citations() {
      return this.messageContentAttributes?.citations || [];
    },
  },
  methods: {
    onResponse(messageResponse) {
      this.$store.dispatch('message/update', messageResponse);
    },
  },
};
</script>

<template>
  <div class="chat-bubble-wrap">
    <component
      :is="contentComponent"
      :message="message"
      :message-id="messageId"
      :message-content-attributes="messageContentAttributes"
      @response="onResponse"
    />
    <CitationList v-if="citations.length" :citations="citations" />
  </div>
</template>
