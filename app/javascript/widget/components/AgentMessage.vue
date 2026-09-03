<script>
import MessageRow from 'widget/components/MessageRow.vue';

/**
 * CASCA (bloco 2.02). A linha da conversa é uma só — `MessageRow.vue` —, e
 * este arquivo é o nome pelo qual `ChatMessage.vue` escolhe o lado do agente.
 *
 * Ele existe por duas razões, não por inércia: `ChatMessage` decide o lado pelo
 * `message_type` e o `<AgentMessage>` no template diz isso em voz alta melhor
 * que uma prop; e o nome do componente é o que aparece na árvore, nas
 * ferramentas de desenvolvedor e nos specs que já existiam.
 */
export default {
  name: 'AgentMessage',
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
    variant="agent"
    :message="message"
    :reply-to="replyTo"
    :classe-agrupamento="classeAgrupamento"
  />
</template>
