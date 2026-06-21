<script setup>
import { computed } from 'vue';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, createdAt, contentAttributes } = useMessageContext();

const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);

// F3: atividade feita por uma IA (marcada no backend via content_attributes.ai_actor)
// ganha a identidade roxa + ícone de bot.
const aiActor = computed(() => contentAttributes.value?.aiActor);
</script>

<template>
  <BaseBubble
    v-tooltip.top="readableTime"
    class="ai-activity-bubble px-3 py-1 !rounded-xl flex min-w-0 items-center gap-2"
    :class="
      aiActor
        ? 'is-ai !bg-n-violet-3 text-n-violet-11 ring-1 ring-n-violet-5'
        : ''
    "
    data-bubble-name="activity"
  >
    <span
      v-if="aiActor"
      class="i-lucide-sparkles size-3.5 flex-shrink-0 text-n-violet-11"
    />
    <span v-dompurify-html="content" :title="content" />
  </BaseBubble>
</template>

<style scoped>
/* Glow suave de "IA ativa" — respeita prefers-reduced-motion. */
.ai-activity-bubble.is-ai {
  animation: ai-activity-glow 3s ease-in-out infinite;
}
@keyframes ai-activity-glow {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgb(var(--violet-9) / 0.18);
  }
  50% {
    box-shadow: 0 0 8px 1px rgb(var(--violet-9) / 0.1);
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-activity-bubble.is-ai {
    animation: none;
  }
}
</style>
