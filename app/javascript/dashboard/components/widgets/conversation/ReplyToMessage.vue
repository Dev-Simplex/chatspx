<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import ReplyPreview from 'dashboard/components-next/message/bubbles/ReplyPreview.vue';

defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['dismiss']);
</script>

<template>
  <div
    class="reply-editor flex items-start gap-2 p-2 mx-2 mt-2 bg-n-slate-3/30 dark:bg-n-alpha-1 rounded-lg border-l-2 border-l-n-brand"
  >
    <div class="flex flex-grow items-center gap-2 min-w-0 mt-px">
      <fluent-icon
        class="flex-shrink-0 icon text-n-brand"
        icon="arrow-reply"
        size="14"
      />
      <span class="text-xs font-medium text-n-brand flex-shrink-0">
        {{ $t('CONVERSATION.REPLYBOX.REPLYING_TO') }}
      </span>
      <ReplyPreview
        :in-reply-to="message"
        class="min-w-0 flex-grow text-sm text-n-slate-11 line-clamp-2"
      />
    </div>
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      ghost
      xs
      slate
      icon="i-lucide-x"
      class="flex-shrink-0 size-6 rounded-full hover:bg-n-slate-3 text-n-slate-10"
      @click.stop="emit('dismiss')"
    />
  </div>
</template>

<style lang="scss">
// TODO: Remove this
// override for dashboard/assets/scss/widgets/_reply-box.scss
.reply-editor {
  .icon {
    margin-right: 0px !important;
  }
}
</style>
