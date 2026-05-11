<script setup>
import { ref, watch, nextTick, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ConversationAPI from 'dashboard/api/conversations';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  open: { type: Boolean, default: false },
});
const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const messages = ref([]); // [{ role: 'user'|'assistant', content: '' }]
const draft = ref('');
const isSending = ref(false);
const messagesEnd = ref(null);

const currentChat = computed(() => store.getters.getSelectedChat);

const loadHistory = async conversationId => {
  if (!conversationId) return;
  try {
    const { data } = await ConversationAPI.copilotHistory(conversationId);
    messages.value = Array.isArray(data?.history) ? data.history : [];
  } catch {
    messages.value = [];
  }
};

watch(
  () => currentChat.value?.id,
  newId => {
    draft.value = '';
    loadHistory(newId);
  },
  { immediate: true }
);

const clearHistory = async () => {
  const conversationId = currentChat.value?.id;
  if (!conversationId) return;
  try {
    await ConversationAPI.clearCopilotHistory(conversationId);
    messages.value = [];
  } catch {
    // ignore
  }
};

const scrollToBottom = () => {
  nextTick(() => {
    messagesEnd.value?.scrollIntoView({ behavior: 'smooth' });
  });
};

const send = async () => {
  const text = draft.value.trim();
  if (!text || isSending.value) return;
  const conversationId = currentChat.value?.id;
  if (!conversationId) return;

  messages.value.push({ role: 'user', content: text });
  draft.value = '';
  isSending.value = true;
  scrollToBottom();
  try {
    const { data } = await ConversationAPI.copilotChat(
      conversationId,
      messages.value
    );
    messages.value.push({
      role: 'assistant',
      content: data?.reply || t('CONVERSATION.COPILOT.NO_REPLY'),
    });
  } catch {
    messages.value.push({
      role: 'assistant',
      content: t('CONVERSATION.COPILOT.ERROR'),
    });
  } finally {
    isSending.value = false;
    scrollToBottom();
  }
};

const onKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  }
};

const quickPrompts = computed(() => [
  t('CONVERSATION.COPILOT.QUICK.SUMMARIZE'),
  t('CONVERSATION.COPILOT.QUICK.NEXT_STEP'),
  t('CONVERSATION.COPILOT.QUICK.WRITE_REPLY'),
]);

const usePrompt = prompt => {
  draft.value = prompt;
  send();
};
</script>

<template>
  <Transition
    enter-active-class="transition-transform duration-200 ease-out"
    enter-from-class="translate-x-full"
    enter-to-class="translate-x-0"
    leave-active-class="transition-transform duration-150 ease-in"
    leave-from-class="translate-x-0"
    leave-to-class="translate-x-full"
  >
    <aside
      v-if="open"
      class="copilot-panel fixed top-0 right-0 z-30 h-full w-[380px] bg-n-solid-1 dark:bg-n-solid-2 border-l border-n-weak shadow-2xl flex flex-col"
    >
      <header
        class="flex items-center justify-between px-4 h-12 border-b border-n-weak"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-sparkles size-4 text-n-brand" />
          <span class="text-sm font-semibold text-n-slate-12">
            {{ t('CONVERSATION.COPILOT.TITLE') }}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <button
            v-if="messages.length"
            v-tooltip="t('CONVERSATION.COPILOT.CLEAR_HISTORY')"
            type="button"
            class="!border-0 !p-0 size-7 grid place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            @click="clearHistory"
          >
            <Icon icon="i-lucide-trash-2" class="size-3.5" />
          </button>
          <button
            type="button"
            class="!border-0 !p-0 size-7 grid place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
      </header>

      <div class="flex-1 overflow-y-auto px-4 py-3 space-y-3">
        <div
          v-if="!messages.length"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-sm text-n-slate-11"
        >
          {{ t('CONVERSATION.COPILOT.WELCOME') }}
        </div>
        <div
          v-for="(m, idx) in messages"
          :key="idx"
          class="flex"
          :class="m.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[85%] px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap"
            :class="
              m.role === 'user'
                ? 'bg-n-brand-default text-white'
                : 'bg-n-alpha-2 text-n-slate-12'
            "
          >
            {{ m.content }}
          </div>
        </div>
        <div v-if="isSending" class="flex justify-start">
          <div
            class="px-3 py-2 rounded-2xl bg-n-alpha-2 text-n-slate-11 text-sm"
          >
            <span
              class="i-lucide-loader-2 size-3 animate-spin inline-block mr-1"
            />
            {{ t('CONVERSATION.COPILOT.THINKING') }}
          </div>
        </div>
        <div ref="messagesEnd" />
      </div>

      <div v-if="!messages.length" class="px-4 pb-2 flex flex-wrap gap-1.5">
        <button
          v-for="prompt in quickPrompts"
          :key="prompt"
          type="button"
          class="!border-0 px-2.5 py-1 rounded-full bg-n-alpha-2 text-xs text-n-slate-11 hover:bg-n-alpha-3"
          @click="usePrompt(prompt)"
        >
          {{ prompt }}
        </button>
      </div>

      <div class="border-t border-n-weak p-3">
        <textarea
          v-model="draft"
          rows="2"
          class="!w-full !p-2.5 !rounded-xl !border !border-n-weak !bg-n-solid-2 dark:!bg-n-solid-3 text-sm text-n-slate-12 resize-none focus:!outline-none focus:!border-n-brand"
          :placeholder="t('CONVERSATION.COPILOT.PLACEHOLDER')"
          @keydown="onKeydown"
        />
        <div
          class="flex justify-between items-center mt-1.5 text-[11px] text-n-slate-10"
        >
          <span>{{ t('CONVERSATION.COPILOT.HINT') }}</span>
          <button
            type="button"
            class="!border-0 px-3 py-1 rounded-md bg-n-brand-default text-white text-xs font-medium hover:opacity-90 disabled:opacity-50"
            :disabled="!draft.trim() || isSending"
            @click="send"
          >
            {{ t('CONVERSATION.COPILOT.SEND') }}
          </button>
        </div>
      </div>
    </aside>
  </Transition>
</template>
