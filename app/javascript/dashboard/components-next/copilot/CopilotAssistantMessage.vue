<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useTrack, useAlert } from 'dashboard/composables';

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

const { t } = useI18n();

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

const feedback = ref(null);

const copyToClipboard = async () => {
  try {
    await navigator.clipboard.writeText(props.message?.content || '');
    useAlert(t('CAPTAIN.COPILOT.ACTIONS.COPIED'));
  } catch (e) {
    /* noop */
  }
};

const setFeedback = val => {
  feedback.value = feedback.value === val ? null : val;
  // TODO backend: emit('feedback', { messageId: props.message.id, value: feedback.value })
};
</script>

<template>
  <div class="flex justify-start">
    <div class="max-w-[90%]">
      <div
        class="bg-n-solid-1 text-n-slate-12 rounded-lg px-3 py-2 text-sm border border-n-weak/50"
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
      <div
        v-if="!hasEmptyMessageContent"
        class="flex items-center gap-1 mt-2 px-1 opacity-60 hover:opacity-100 transition-opacity"
      >
        <button
          v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.COPY')"
          type="button"
          class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :aria-label="$t('CAPTAIN.COPILOT.ACTIONS.COPY')"
          @click="copyToClipboard"
        >
          <span class="i-lucide-copy size-3.5" aria-hidden="true" />
        </button>
        <button
          v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.GOOD')"
          type="button"
          class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :class="{ '!text-n-teal-10 !bg-n-teal-3': feedback === 'up' }"
          :aria-label="$t('CAPTAIN.COPILOT.ACTIONS.GOOD')"
          :aria-pressed="feedback === 'up'"
          @click="setFeedback('up')"
        >
          <span class="i-lucide-thumbs-up size-3.5" aria-hidden="true" />
        </button>
        <button
          v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.BAD')"
          type="button"
          class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40"
          :class="{ '!text-n-ruby-10 !bg-n-ruby-3': feedback === 'down' }"
          :aria-label="$t('CAPTAIN.COPILOT.ACTIONS.BAD')"
          :aria-pressed="feedback === 'down'"
          @click="setFeedback('down')"
        >
          <span class="i-lucide-thumbs-down size-3.5" aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>
</template>
