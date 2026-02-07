<script>
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { REPLY_EDITOR_MODES, CHAR_LENGTH_WARNING } from './constants';
import EditorModeToggle from './EditorModeToggle.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  name: 'ReplyTopPanel',
  components: {
    EditorModeToggle,
    NextButton,
  },
  props: {
    mode: {
      type: String,
      default: REPLY_EDITOR_MODES.REPLY,
    },
    isReplyRestricted: {
      type: Boolean,
      default: false,
    },
    isMessageLengthReachingThreshold: {
      type: Boolean,
      default: () => false,
    },
    charactersRemaining: {
      type: Number,
      default: () => 0,
    },
    popOutReplyBox: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['setReplyMode', 'closePopout'],
  setup(props, { emit }) {
    const setReplyMode = mode => {
      emit('setReplyMode', mode);
    };
    const handleReplyClick = () => {
      if (props.isReplyRestricted) return;
      setReplyMode(REPLY_EDITOR_MODES.REPLY);
    };
    const handleNoteClick = () => {
      setReplyMode(REPLY_EDITOR_MODES.NOTE);
    };
    const handleModeToggle = () => {
      const newMode =
        props.mode === REPLY_EDITOR_MODES.REPLY
          ? REPLY_EDITOR_MODES.NOTE
          : REPLY_EDITOR_MODES.REPLY;
      setReplyMode(newMode);
    };
    const keyboardEvents = {
      'Alt+KeyP': {
        action: () => handleNoteClick(),
        allowOnFocusedInput: true,
      },
      'Alt+KeyL': {
        action: () => handleReplyClick(),
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);

    return {
      handleModeToggle,
      handleReplyClick,
      handleNoteClick,
      REPLY_EDITOR_MODES,
    };
  },
  computed: {
    replyButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.REPLY,
      };
    },
    noteButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.NOTE,
      };
    },
    charLengthClass() {
      return this.charactersRemaining < 0 ? 'text-n-ruby-9' : 'text-n-slate-11';
    },
    characterLengthWarning() {
      return this.charactersRemaining < 0
        ? `${-this.charactersRemaining} ${CHAR_LENGTH_WARNING.NEGATIVE}`
        : `${this.charactersRemaining} ${CHAR_LENGTH_WARNING.UNDER_50}`;
    },
  },
};
</script>

<template>
  <div class="flex justify-between h-[2.5rem] gap-2 ltr:pl-2 rtl:pr-2 ltr:pr-2 rtl:pl-2">
    <EditorModeToggle
      :mode="mode"
      :disabled="isReplyRestricted"
      class="my-1.5"
      @toggle-mode="handleModeToggle"
    />
    <div class="flex flex-1 items-center justify-center mx-2 my-0 min-w-0">
      <div v-if="isMessageLengthReachingThreshold" class="text-[11px] text-n-slate-11">
        <span :class="charLengthClass">
          {{ characterLengthWarning }}
        </span>
      </div>
    </div>
    <NextButton
      v-if="popOutReplyBox"
      v-tooltip.top-end="$t('CONVERSATION.HEADER.CLOSE')"
      ghost
      icon="i-ph-x"
      class="my-1.5 shrink-0 !size-8"
      @click="$emit('closePopout')"
    />
  </div>
</template>
