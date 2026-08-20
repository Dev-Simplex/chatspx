<script>
import ChatForm from 'shared/components/ChatForm.vue';
import CaptureForm from 'widget/capture/CaptureForm.vue';

/**
 * Bloco 4.03 — dois desenhos para o mesmo `content_type: 'form'`, e a escolha é
 * pelo CONTEÚDO do passo, não por configuração:
 *
 *  · passo que declara `mask`, `validator` ou um campo de telefone → `CaptureForm`,
 *    que sabe mascarar no blur, validar com as regras BR (bloco 3.13) e aplicar a
 *    regra "e-mail OU WhatsApp";
 *  · qualquer outro → `ChatForm`, exatamente como hoje. **Zero regressão** para o
 *    formulário que já existe: um `form` gravado antes deste bloco não tem
 *    nenhuma dessas chaves, então cai no caminho de sempre.
 *
 * Não é um `if` de conveniência: `ChatForm` mora em `shared/` e é renderizado
 * também pelo dashboard, então ensiná-lo máscara brasileira arrastaria a outra
 * superfície junto (regra R21). O componente novo é do widget.
 */
export default {
  name: 'FormContent',
  components: { ChatForm, CaptureForm },
  inheritAttrs: false,
  props: {
    messageId: { type: Number, default: null },
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
  emits: ['response'],
  computed: {
    items() {
      return this.messageContentAttributes.items || [];
    },
    isAnswered() {
      return Boolean(this.messageContentAttributes.submitted_values);
    },
    needsCapture() {
      return this.items.some(
        item => item && (item.mask || item.validator || item.type === 'phone')
      );
    },
  },
  methods: {
    onFormSubmit(formValues) {
      const formValuesAsArray = Object.keys(formValues).map(key => ({
        name: key,
        value: formValues[key],
      }));
      this.emitResponse(formValuesAsArray);
    },
    emitResponse(submittedValues) {
      this.$emit('response', { submittedValues, messageId: this.messageId });
    },
  },
};
</script>

<template>
  <!-- Formulário já respondido não desenha nada: nem o formulário, nem a
       bolha de texto. É o comportamento de hoje, preservado de propósito. -->
  <CaptureForm
    v-if="!isAnswered && needsCapture"
    :items="items"
    :button-label="messageContentAttributes.button_label"
    @submit="emitResponse"
  />
  <ChatForm
    v-else-if="!isAnswered"
    :items="items"
    :button-label="messageContentAttributes.button_label"
    :submitted-values="messageContentAttributes.submitted_values"
    @submit="onFormSubmit"
  />
</template>
