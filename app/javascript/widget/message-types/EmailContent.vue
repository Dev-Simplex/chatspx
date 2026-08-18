<script>
import TextContent from './TextContent.vue';
import EmailInput from 'widget/components/template/EmailInput.vue';

export default {
  name: 'EmailContent',
  components: { TextContent, EmailInput },
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
    messageId: { type: Number, default: null },
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
};
</script>

<template>
  <TextContent :message="message">
    <EmailInput
      :message-id="messageId"
      :message-content-attributes="messageContentAttributes"
    />
  </TextContent>
</template>
