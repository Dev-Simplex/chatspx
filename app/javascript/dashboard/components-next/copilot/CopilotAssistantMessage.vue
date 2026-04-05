<script setup>
import { computed } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useTrack } from 'dashboard/composables';

import { BUS_EVENTS } from 'shared/constants/busEvents';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isLastMessage: {
    type: Boolean,
    default: false,
  },
  message: {
    type: Object,
    required: true,
  },
  conversationInboxType: {
    type: String,
    required: true,
  },
});
const hasEmptyMessageContent = computed(() => !props.message?.content);

const showUseButton = computed(() => {
  return (
    !hasEmptyMessageContent.value &&
    props.message.reply_suggestion &&
    props.isLastMessage
  );
});

const messageContent = computed(() => {
  const formatter = new MessageFormatter(props.message.content);
  return formatter.formattedMessage;
});

const insertIntoRichEditor = computed(() => {
  return [INBOX_TYPES.WEB, INBOX_TYPES.EMAIL].includes(
    props.conversationInboxType
  );
});

const useCopilotResponse = () => {
  if (insertIntoRichEditor.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, props.message?.content);
  } else {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, props.message?.content);
  }
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
};
</script>

<template>
  <div class="flex justify-start">
    <div class="max-w-[90%]">
      <div
        class="bg-white dark:bg-n-solid-3 text-n-slate-12 rounded-lg px-3 py-2 text-sm border border-n-weak/50"
      >
        <span v-if="hasEmptyMessageContent" class="text-n-ruby-11">
          {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
        </span>
        <div
          v-else
          v-dompurify-html="messageContent"
          class="prose-sm break-words"
        />
      </div>
      <div v-if="showUseButton" class="flex items-center gap-2 mt-2">
        <Button
          :label="$t('CAPTAIN.COPILOT.USE')"
          sm
          class="!px-3 !h-7 !rounded-lg !bg-n-brand !text-white !text-xs !font-medium hover:!bg-n-brand-hover"
          @click="useCopilotResponse"
        />
      </div>
    </div>
  </div>
</template>
