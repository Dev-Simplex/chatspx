<script setup>
import { ref, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  messageId: { type: Number, required: true },
  conversationId: { type: Number, required: true },
  initialContent: { type: String, default: '' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const editedContent = ref(props.initialContent);
const isLoading = ref(false);
const textareaRef = ref(null);

onMounted(() => {
  nextTick(() => {
    if (!textareaRef.value) return;
    textareaRef.value.focus();
    const len = editedContent.value.length;
    textareaRef.value.setSelectionRange(len, len);
    autoResize();
  });
});

function autoResize() {
  if (!textareaRef.value) return;
  textareaRef.value.style.height = 'auto';
  textareaRef.value.style.height = `${textareaRef.value.scrollHeight}px`;
}

async function handleSave() {
  const trimmed = editedContent.value.trim();
  if (!trimmed) return;
  if (trimmed === props.initialContent) {
    emit('close');
    return;
  }
  isLoading.value = true;
  try {
    await store.dispatch('updateMessageContent', {
      conversationId: props.conversationId,
      messageId: props.messageId,
      content: trimmed,
    });
    useAlert(t('CONVERSATION.EDIT_MESSAGE.SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('CONVERSATION.EDIT_MESSAGE.ERROR'));
  } finally {
    isLoading.value = false;
  }
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    handleSave();
  }
  if (e.key === 'Escape') {
    emit('close');
  }
}
</script>

<template>
  <div class="flex flex-col gap-2 w-full py-1">
    <textarea
      ref="textareaRef"
      v-model="editedContent"
      rows="1"
      class="w-full resize-none overflow-hidden rounded-lg border px-3 py-2 text-sm bg-n-background text-n-slate-12 outline-none leading-relaxed border-n-strong focus:border-woot-500 focus:ring-1 focus:ring-woot-500 disabled:opacity-50 transition-colors"
      :disabled="isLoading"
      @input="autoResize"
      @keydown="handleKeydown"
    />
    <div class="flex items-center gap-2">
      <NextButton
        sm
        :label="t('CONVERSATION.EDIT_MESSAGE.SAVE')"
        :is-loading="isLoading"
        :disabled="isLoading || !editedContent.trim()"
        @click="handleSave"
      />
      <NextButton
        sm
        ghost
        slate
        :label="t('CONVERSATION.EDIT_MESSAGE.CANCEL')"
        :disabled="isLoading"
        @click="emit('close')"
      />
      <span class="text-xs text-n-slate-11 select-none">
        {{ t('CONVERSATION.EDIT_MESSAGE.HINT') }}
      </span>
    </div>
  </div>
</template>
