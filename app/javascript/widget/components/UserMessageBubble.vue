<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

export default {
  name: 'UserMessageBubble',
  props: {
    message: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { formatMessage } = useMessageFormatter();
    return {
      formatMessage,
    };
  },
};
</script>

<template>
  <div
    v-dompurify-html="formatMessage(message, false)"
    class="chat-bubble user bg-w-brand text-w-on-brand"
  />
</template>

<style lang="scss" scoped>
.chat-bubble.user {
  :deep(p code) {
    @apply bg-n-alpha-2 dark:bg-n-alpha-1 text-white;
  }

  :deep(pre) {
    @apply text-white bg-n-alpha-2 dark:bg-n-alpha-1;

    code {
      @apply bg-transparent text-white;
    }
  }

  :deep(blockquote) {
    @apply bg-transparent border-n-slate-7 ltr:border-l-2 rtl:border-r-2 border-solid;

    p {
      @apply text-n-slate-5 dark:text-n-slate-12/90;
    }
  }
}
</style>
