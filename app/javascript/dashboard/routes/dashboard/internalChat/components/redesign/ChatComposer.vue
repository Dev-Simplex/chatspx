<script setup>
import { ref, nextTick, defineAsyncComponent } from 'vue';

const emit = defineEmits(['send']);

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const draft = ref('');
const showEmoji = ref(false);
const textareaRef = ref(null);

const autoResize = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 112)}px`;
};

const toggleEmoji = () => {
  showEmoji.value = !showEmoji.value;
};

const onEmojiSelect = emoji => {
  draft.value += emoji;
  showEmoji.value = false;
  nextTick(() => {
    textareaRef.value?.focus();
    autoResize();
  });
};

const send = () => {
  const content = draft.value.trim();
  if (!content) return;
  emit('send', content);
  draft.value = '';
  showEmoji.value = false;
  nextTick(autoResize);
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="relative px-4 pb-3 md:px-6 flex-shrink-0 bg-n-background">
    <!-- Single-row composer pill -->
    <div
      class="relative z-20 flex items-center gap-1 px-2 py-1 transition-colors border shadow-sm rounded-2xl bg-n-solid-1 border-n-weak focus-within:border-n-brand"
    >
      <!-- Emoji: o picker abre ACIMA do ícone (ancorado ao botão, à esquerda) -->
      <div class="relative flex-shrink-0">
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showEmoji ? 'text-n-brand bg-n-alpha-2' : ''"
          title="Emoji"
          @click="toggleEmoji"
        >
          <span class="text-lg i-lucide-smile" />
        </button>
        <template v-if="showEmoji">
          <div class="fixed inset-0 z-10" @click="showEmoji = false" />
          <div class="absolute z-20 bottom-full mb-2 left-0">
            <EmojiInput :on-click="onEmojiSelect" />
          </div>
        </template>
      </div>
      <textarea
        ref="textareaRef"
        v-model="draft"
        rows="1"
        placeholder="Digite sua mensagem..."
        class="reset-base flex-1 h-auto min-h-0 px-1 py-1.5 mb-0 text-sm bg-transparent outline-none resize-none text-n-slate-12 placeholder:text-n-slate-10 max-h-28 leading-snug"
        @input="autoResize"
        @keydown.enter.exact.prevent="send"
      />
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 text-white transition-all rounded-full shadow-sm bg-n-brand hover:bg-n-brand-hover active:scale-90 disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100"
        title="Enviar"
        :disabled="!draft.trim()"
        @click="send"
      >
        <span class="text-lg i-lucide-send-horizontal" />
      </button>
    </div>
  </div>
</template>
