<script setup>
import { ref, nextTick, onMounted } from 'vue';

const emit = defineEmits(['send']);
const message = ref('');
const textareaRef = ref(null);

const adjustHeight = () => {
  if (!textareaRef.value) return;

  // Reset height to auto to get the correct scrollHeight
  textareaRef.value.style.height = 'auto';
  // Set the height to the scrollHeight
  textareaRef.value.style.height = `${textareaRef.value.scrollHeight}px`;
};

const sendMessage = () => {
  if (message.value.trim()) {
    emit('send', message.value);
    message.value = '';
    // Reset textarea height after sending
    nextTick(() => {
      adjustHeight();
    });
  }
};

const handleInput = () => {
  nextTick(adjustHeight);
};

const handleEnterKey = event => {
  if (event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

onMounted(() => {
  nextTick(adjustHeight);
});
</script>

<template>
  <form class="relative flex items-end gap-2" @submit.prevent="sendMessage">
    <textarea
      ref="textareaRef"
      v-model="message"
      :placeholder="$t('CAPTAIN.COPILOT.SEND_MESSAGE')"
      class="w-full reset-base bg-white dark:bg-n-solid-3 ltr:pl-3 ltr:pr-3 rtl:pl-3 rtl:pr-3 py-2 text-sm border border-n-weak rounded-lg focus:outline-0 focus:outline-none focus:ring-1 focus:ring-n-brand/20 focus:border-n-brand/50 resize-none overflow-hidden max-h-[200px] mb-0 text-n-slate-12 placeholder:text-n-slate-9"
      rows="1"
      @input="handleInput"
      @keydown.enter.exact="handleEnterKey"
    />
    <button
      class="size-8 flex-shrink-0 flex items-center justify-center rounded-full bg-n-brand text-white hover:bg-n-brand-hover transition-colors"
      type="submit"
    >
      <i class="i-lucide-send-horizontal size-4" />
    </button>
  </form>
</template>
