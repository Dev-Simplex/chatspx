<script>
import CustomerSatisfaction from 'shared/components/CustomerSatisfaction.vue';

export default {
  name: 'CsatContent',
  components: { CustomerSatisfaction },
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
    messageId: { type: Number, default: null },
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
};
</script>

<template>
  <CustomerSatisfaction
    :message-content-attributes="messageContentAttributes.submitted_values"
    :display-type="messageContentAttributes.display_type"
    :message="message"
    :message-id="messageId"
  />
</template>
