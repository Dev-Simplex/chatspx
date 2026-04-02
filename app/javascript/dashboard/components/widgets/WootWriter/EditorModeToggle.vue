<script setup>
import { computed } from 'vue';
import { REPLY_EDITOR_MODES } from './constants';

const props = defineProps({
  mode: {
    type: String,
    default: REPLY_EDITOR_MODES.REPLY,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isReplyRestricted: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['toggleMode']);

const isPrivate = computed(() => {
  if (props.isReplyRestricted) {
    return true;
  }
  return props.mode === REPLY_EDITOR_MODES.NOTE;
});
</script>

<template>
  <div
    class="flex items-center gap-1 p-1 bg-n-slate-3/50 dark:bg-n-alpha-2 rounded-lg"
  >
    <button
      class="relative z-20 px-3 py-1 text-sm rounded-md transition-all duration-200"
      :class="[
        !isPrivate
          ? 'bg-white dark:bg-n-solid-2 text-n-slate-12 shadow-sm font-medium'
          : 'text-n-slate-10 hover:text-n-slate-12',
        { 'cursor-not-allowed opacity-50': disabled || isReplyRestricted },
      ]"
      :disabled="disabled || isReplyRestricted"
      @click="!isPrivate || $emit('toggleMode')"
    >
      {{ $t('CONVERSATION.REPLYBOX.REPLY') }}
    </button>
    <button
      class="relative z-20 px-3 py-1 text-sm rounded-md transition-all duration-200"
      :class="[
        isPrivate
          ? 'bg-n-amber-3 dark:bg-n-amber-5/30 text-n-amber-11 shadow-sm font-medium'
          : 'text-n-slate-10 hover:text-n-slate-12',
        { 'cursor-not-allowed': disabled },
      ]"
      :disabled="disabled"
      @click="isPrivate || $emit('toggleMode')"
    >
      {{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE') }}
    </button>
  </div>
</template>
