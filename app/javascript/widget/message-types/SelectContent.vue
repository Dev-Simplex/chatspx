<script>
import ChatOptions from 'shared/components/ChatOptions.vue';

export default {
  name: 'SelectContent',
  components: { ChatOptions },
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
    messageId: { type: Number, default: null },
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
  emits: ['response'],
  methods: {
    onOptionSelect(selectedOption) {
      this.$emit('response', {
        submittedValues: [selectedOption],
        messageId: this.messageId,
      });
    },
  },
};
</script>

<template>
  <div>
    <ChatOptions
      :title="message"
      :options="messageContentAttributes.items"
      :hide-fields="!!messageContentAttributes.submitted_values"
      @option-select="onOptionSelect"
    />
  </div>
</template>
