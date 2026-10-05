<script setup>
import { ref, watch, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageBubble from './MessageBubble.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
  loading: { type: Boolean, default: false },
  loadingOlder: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
  searching: { type: Boolean, default: false },
  mentionNames: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'react',
  'edit',
  'delete',
  'reply',
  'retry',
  'loadOlder',
]);

const { t } = useI18n();
const scroller = ref(null);

// Rola até a mensagem citada e a destaca por um instante (clique no reply).
const scrollToMessage = id => {
  const el = scroller.value?.querySelector(`[data-msg-id="${id}"]`);
  if (!el) return;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.classList.add('ring-2', 'ring-n-brand/60', 'rounded-2xl');
  setTimeout(
    () => el.classList.remove('ring-2', 'ring-n-brand/60', 'rounded-2xl'),
    1400
  );
};

const scrollToBottom = (smooth = false) => {
  const el = scroller.value;
  if (!el) return;
  el.scrollTo({ top: el.scrollHeight, behavior: smooth ? 'smooth' : 'auto' });
};

// Chegou perto do topo → pede as mensagens anteriores.
const onScroll = () => {
  const el = scroller.value;
  if (el && el.scrollTop < 80 && props.hasMore && !props.loadingOlder) {
    emit('loadOlder');
  }
};

// Ao abrir/trocar de conversa (remontagem via :key) já mostra o fim da thread.
onMounted(() => nextTick(() => scrollToBottom(false)));

// Mensagens antigas entraram em cima → mantém o que estava na tela parado.
// Mensagem nova embaixo → desce suave acompanhando o balão.
watch(
  () => props.items,
  (next, prev) => {
    const el = scroller.value;
    if (!el || next.length <= prev.length) return;
    const prepended =
      prev.length > 0 && next.at(-1)?.id === prev.at(-1)?.id;
    if (prepended) {
      const fromBottom = el.scrollHeight - el.scrollTop;
      nextTick(() => {
        el.scrollTop = el.scrollHeight - fromBottom;
      });
    } else {
      nextTick(() => scrollToBottom(prev.length > 0));
    }
  }
);
</script>

<template>
  <div
    ref="scroller"
    class="flex-1 min-h-0 px-4 py-5 overflow-y-auto md:px-8 bg-n-background"
    @scroll.passive="onScroll"
  >
    <!-- Carregando a conversa pela primeira vez -->
    <div
      v-if="loading && !items.length"
      class="flex items-center justify-center h-full gap-2 text-sm text-n-slate-11"
    >
      <span class="i-lucide-loader-circle animate-spin" />
      {{ t('INTERNAL_CHAT.THREAD.LOADING') }}
    </div>

    <!-- Conversa sem mensagens (ou busca sem resultado) -->
    <div
      v-else-if="!items.length"
      class="flex flex-col items-center justify-center h-full gap-2 text-center"
    >
      <span
        class="text-3xl text-n-slate-9"
        :class="searching ? 'i-lucide-search-x' : 'i-lucide-message-circle'"
      />
      <p class="text-sm font-medium text-n-slate-12">
        {{
          searching
            ? t('INTERNAL_CHAT.THREAD.NO_MATCH')
            : t('INTERNAL_CHAT.THREAD.EMPTY_TITLE')
        }}
      </p>
      <p v-if="!searching" class="max-w-xs text-xs text-n-slate-11">
        {{ t('INTERNAL_CHAT.THREAD.EMPTY_HINT') }}
      </p>
    </div>

    <template v-else>
      <!-- Topo: carregando antigas / botão / início da conversa -->
      <div class="flex justify-center pb-3">
        <span
          v-if="loadingOlder"
          class="flex items-center gap-2 text-xs text-n-slate-11"
        >
          <span class="i-lucide-loader-circle animate-spin" />
          {{ t('INTERNAL_CHAT.THREAD.LOADING_OLDER') }}
        </span>
        <button
          v-else-if="hasMore"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded-full text-n-slate-11 bg-n-alpha-1 hover:bg-n-alpha-2"
          @click="emit('loadOlder')"
        >
          {{ t('INTERNAL_CHAT.THREAD.LOAD_OLDER') }}
        </button>
        <span v-else-if="!searching" class="text-[11px] text-n-slate-10">
          {{ t('INTERNAL_CHAT.THREAD.START') }}
        </span>
      </div>

      <div
        v-for="item in items"
        :key="item.id"
        :class="item.type === 'message' && item.continued ? 'mt-0.5' : 'mt-3'"
      >
        <!-- Separador de dia -->
        <div
          v-if="item.type === 'day'"
          class="sticky top-0 z-10 flex justify-center py-1"
        >
          <span
            class="px-3 py-1 text-[11px] font-medium rounded-full shadow-sm text-n-slate-11 bg-n-solid-2 first-letter:uppercase"
          >
            {{ item.label }}
          </span>
        </div>

        <!-- Mensagem -->
        <MessageBubble
          v-else
          :message="item"
          :current-user-id="currentUserId"
          :mention-names="mentionNames"
          @react="emit('react', $event)"
          @edit="emit('edit', $event)"
          @delete="emit('delete', $event)"
          @reply="emit('reply', $event)"
          @retry="emit('retry', $event)"
          @scroll-to="scrollToMessage"
        />
      </div>
    </template>
  </div>
</template>
