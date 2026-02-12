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
    class="reply-editor bg-n-slate-9/10 rounded-md py-1 pl-2 pr-1 text-xs tracking-wide mt-2 flex items-center gap-1.5 -mx-2"
  >
    <fluent-icon class="flex-shrink-0 icon" icon="arrow-reply" size="14" />
    <div class="flex flex-grow items-center gap-2 min-w-0 mt-px text-xs">
      <span class="flex-shrink-0">
        {{ $t('CONVERSATION.REPLYBOX.REPLYING_TO') }}
      </span>
      <ReplyPreview :in-reply-to="message" class="min-w-0 flex-grow" />
    </div>
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      ghost
      xs
      slate
      icon="i-lucide-x"
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
