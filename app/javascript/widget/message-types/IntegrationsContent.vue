<script>
import TextContent from './TextContent.vue';
import IntegrationCard from 'widget/components/template/IntegrationCard.vue';

export default {
  name: 'IntegrationsContent',
  components: { TextContent, IntegrationCard },
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
    messageId: { type: Number, default: null },
  },
};
</script>

<template>
  <TextContent :message="message">
    <!-- `meeting-data` não é passado: o IntegrationCard nunca declarou essa
         prop — ele busca o token da chamada pela API, pelo `messageId`. -->
    <IntegrationCard :message-id="messageId" />
  </TextContent>
</template>
