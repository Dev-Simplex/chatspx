<script>
import ChatForm from 'shared/components/ChatForm.vue';

export default {
  name: 'FormContent',
  components: { ChatForm },
  inheritAttrs: false,
  props: {
    messageId: { type: Number, default: null },
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
  emits: ['response'],
  methods: {
    onFormSubmit(formValues) {
      const formValuesAsArray = Object.keys(formValues).map(key => ({
        name: key,
        value: formValues[key],
      }));
      this.$emit('response', {
        submittedValues: formValuesAsArray,
        messageId: this.messageId,
      });
    },
  },
};
</script>

<template>
  <!-- Formulário já respondido não desenha nada: nem o formulário, nem a
       bolha de texto. É o comportamento de hoje, preservado de propósito. -->
  <ChatForm
    v-if="!messageContentAttributes.submitted_values"
    :items="messageContentAttributes.items"
    :button-label="messageContentAttributes.button_label"
    :submitted-values="messageContentAttributes.submitted_values"
    @submit="onFormSubmit"
  />
</template>
