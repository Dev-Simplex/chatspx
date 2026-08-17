<script>
import WTypingDots from 'widget/components/WTypingDots.vue';

export default {
  name: 'AgentTypingBubble',
  components: { WTypingDots },
};
</script>

<template>
  <div class="agent-message-wrap sticky bottom-1">
    <div class="agent-message">
      <div class="avatar-wrap" />
      <div class="message-wrap mt-2">
        <!-- Era um `<img src="assets/images/typing.gif">` de 19.296 B, baixado
             na primeira vez que um agente digitava. Três pontos em CSS custam 0
             requisição e 0 byte de rede, respeitam `prefers-reduced-motion` e
             acompanham o tema — o GIF tinha fundo branco cravado. -->
        <div class="chat-bubble agent typing-bubble bg-white dark:bg-n-solid-3">
          <WTypingDots />
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.typing-bubble {
  @apply max-w-[2.4rem] p-2 ltr:rounded-bl-[1.25rem] rtl:rounded-br-[1.25rem] ltr:rounded-tl-lg rtl:rounded-tr-lg;
}
</style>
