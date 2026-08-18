<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

export default {
  name: 'TextContent',
  // Os tipos do registry recebem o mesmo trio de props; cada um declara só o
  // que usa. Sem isto, o que sobra desceria para o DOM como atributo solto —
  // que é exatamente o defeito do `meeting-data` que este bloco corrigiu.
  inheritAttrs: false,
  props: {
    message: { type: String, default: null },
  },
  setup() {
    const { formatMessage } = useMessageFormatter();
    return { formatMessage };
  },
};
</script>

<template>
  <div class="chat-bubble agent bg-white dark:bg-n-solid-3 text-n-slate-12">
    <div
      v-dompurify-html="formatMessage(message, false)"
      class="message-content text-n-slate-12"
    />
    <!-- input_email e integrations desenham DENTRO da bolha de texto, ao
         contrário dos outros cinco tipos ricos, que a substituem. -->
    <slot />
  </div>
</template>
