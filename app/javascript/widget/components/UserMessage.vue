<script>
import MessageRow from 'widget/components/MessageRow.vue';

/**
 * CASCA (bloco 2.02) — o lado do visitante da linha única `MessageRow.vue`.
 * Ver a nota de `AgentMessage.vue` para o porquê de a casca existir.
 */
export default {
  name: 'UserMessage',
  components: { MessageRow },
  props: {
    message: { type: Object, default: () => {} },
    replyTo: { type: Object, default: () => {} },
    classeAgrupamento: { type: String, default: null },
  },
};
</script>

<template>
  <MessageRow
    variant="user"
    :message="message"
    :reply-to="replyTo"
    :classe-agrupamento="classeAgrupamento"
  />
</template>
