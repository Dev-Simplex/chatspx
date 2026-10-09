<script setup>
import { ref, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageBubble from './MessageBubble.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
  loading: { type: Boolean, default: false },
  loadError: { type: Boolean, default: false },
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
  'reload',
  'forward',
  'info',
  'star',
  'replyPrivately',
]);

const { t } = useI18n();
const scroller = ref(null);

// Rola até a mensagem citada e a destaca por um instante (clique no reply e
// resultado da busca). Devolve se achou (a mensagem pode não estar carregada).
const scrollToMessage = id => {
  const el = scroller.value?.querySelector(`[data-msg-id="${id}"]`);
  if (!el) return false;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.classList.add('ring-2', 'ring-n-teal-9/60', 'rounded-2xl');
  setTimeout(
    () => el.classList.remove('ring-2', 'ring-n-teal-9/60', 'rounded-2xl'),
    1400
  );
  return true;
};
defineExpose({ scrollToMessage });

const scrollToBottom = (smooth = false) => {
  const el = scroller.value;
  if (!el) return;
  el.scrollTo({ top: el.scrollHeight, behavior: smooth ? 'smooth' : 'auto' });
};

// "Ir para o fim": aparece quando a pessoa sobe na conversa e conta as
// mensagens que chegaram enquanto ela estava lá em cima.
const NEAR_BOTTOM = 120;
const atBottom = ref(true);
const newWhileAway = ref(0);
const goToBottom = () => {
  newWhileAway.value = 0;
  scrollToBottom(true);
};

// Chegou perto do topo → pede as mensagens anteriores.
const onScroll = () => {
  const el = scroller.value;
  if (!el) return;
  atBottom.value =
    el.scrollHeight - el.scrollTop - el.clientHeight < NEAR_BOTTOM;
  if (atBottom.value) newWhileAway.value = 0;
  if (el.scrollTop < 80 && props.hasMore && !props.loadingOlder) {
    emit('loadOlder');
  }
};

// Ao abrir/trocar de conversa (remontagem via :key) já mostra o fim da thread.
// Conteúdo que cresce depois (prévia de link, imagem carregando) mantém quem
// estava no fim colado no fim.
const content = ref(null);
let resizeObserver = null;
onMounted(() => {
  nextTick(() => scrollToBottom(false));
  if (typeof ResizeObserver === 'undefined') return;
  resizeObserver = new ResizeObserver(() => {
    if (atBottom.value) scrollToBottom(false);
  });
  if (content.value) resizeObserver.observe(content.value);
});
// A lista só existe depois de carregar: passa a observar quando aparece.
watch(content, (el, old) => {
  if (old) resizeObserver?.unobserve(old);
  if (el) resizeObserver?.observe(el);
});
onBeforeUnmount(() => resizeObserver?.disconnect());

// Mensagens antigas entraram em cima → mantém o que estava na tela parado.
// Mensagem nova embaixo → desce suave acompanhando o balão.
watch(
  () => props.items,
  (next, prev) => {
    const el = scroller.value;
    if (!el || next.length <= prev.length) return;
    const prepended = prev.length > 0 && next.at(-1)?.id === prev.at(-1)?.id;
    if (prepended) {
      const fromBottom = el.scrollHeight - el.scrollTop;
      nextTick(() => {
        el.scrollTop = el.scrollHeight - fromBottom;
      });
      return;
    }
    // Lendo lá em cima: não puxa a tela; só conta as novas dos outros (a
    // minha própria mensagem sempre desce).
    const lastPrev = prev.findLastIndex(i => i.type === 'message');
    const lastId = lastPrev === -1 ? null : prev[lastPrev].id;
    const from = next.findIndex(i => i.id === lastId);
    const added = next.slice(from + 1).filter(i => i.type === 'message');
    const sentByMe = added.some(i => i.mine);
    if (prev.length > 0 && !atBottom.value && !sentByMe) {
      newWhileAway.value += added.length;
      return;
    }
    nextTick(() => scrollToBottom(prev.length > 0));
  }
);
</script>

<template>
  <div class="relative flex flex-col flex-1 min-h-0">
    <div
      ref="scroller"
      class="flex-1 min-h-0 px-3 pt-2 pb-4 overflow-y-auto md:px-6 bg-n-background"
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

      <!-- Não carregou: diz e oferece tentar de novo -->
      <div
        v-else-if="loadError && !items.length"
        class="flex flex-col items-center justify-center h-full gap-3 text-center"
      >
        <span class="text-2xl i-lucide-wifi-off text-n-ruby-11" />
        <p class="mb-0 text-sm text-n-slate-12">
          {{ t('INTERNAL_CHAT.THREAD.LOAD_ERROR') }}
        </p>
        <button
          type="button"
          class="px-4 py-1.5 text-xs font-semibold rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
          @click="emit('reload')"
        >
          {{ t('INTERNAL_CHAT.RETRY') }}
        </button>
      </div>

      <!-- Conversa sem mensagens (ou busca sem resultado) -->
      <div
        v-else-if="!items.length"
        class="flex flex-col items-center justify-center h-full gap-2 text-center"
      >
        <span
          class="flex items-center justify-center mb-1 rounded-full size-14 bg-n-alpha-2"
        >
          <span
            class="text-2xl text-n-slate-10"
            :class="searching ? 'i-lucide-search-x' : 'i-lucide-message-circle'"
          />
        </span>
        <p class="text-base font-semibold text-n-slate-12">
          {{
            searching
              ? t('INTERNAL_CHAT.THREAD.NO_MATCH')
              : t('INTERNAL_CHAT.THREAD.EMPTY_TITLE')
          }}
        </p>
        <p v-if="!searching" class="max-w-xs text-sm text-n-slate-11">
          {{ t('INTERNAL_CHAT.THREAD.EMPTY_HINT') }}
        </p>
      </div>

      <div v-else ref="content">
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
          :class="
            item.type === 'message' ? (item.continued ? 'mt-0.5' : 'mt-3') : ''
          "
        >
          <!-- Horário centralizado acima do bloco ("Hoje 09:02") -->
          <div
            v-if="item.type === 'stamp'"
            class="flex justify-center pt-5 pb-1 text-[11px] text-n-slate-10"
          >
            <span>
              <span class="font-semibold first-letter:uppercase inline-block">
                {{ item.day }}
              </span>
              {{ item.time }}
            </span>
          </div>

          <!-- Onde começam as mensagens que chegaram enquanto você não via -->
          <div
            v-else-if="item.type === 'new'"
            data-new-marker
            class="flex items-center gap-3 pt-4 pb-1 text-[11px] font-semibold text-n-teal-11"
          >
            <span class="flex-1 h-px bg-n-teal-9/40" />
            {{ t('INTERNAL_CHAT.THREAD.NEW_MESSAGES') }}
            <span class="flex-1 h-px bg-n-teal-9/40" />
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
            @forward="emit('forward', $event)"
            @info="emit('info', $event)"
            @star="emit('star', $event)"
            @reply-privately="emit('replyPrivately', $event)"
            @scroll-to="scrollToMessage"
          />
        </div>
      </div>
    </div>

    <!-- Ir para o fim (com quantas chegaram enquanto estava lá em cima) -->
    <button
      v-if="!atBottom && items.length"
      v-tooltip.left="
        newWhileAway
          ? t('INTERNAL_CHAT.THREAD.GO_BOTTOM_NEW', { count: newWhileAway })
          : t('INTERNAL_CHAT.THREAD.GO_BOTTOM')
      "
      type="button"
      class="absolute z-10 inline-flex items-center justify-center border rounded-full shadow-lg bottom-3 right-4 md:right-6 size-10 bg-n-solid-1 dark:bg-n-solid-3 border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-solid-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
      :aria-label="
        newWhileAway
          ? t('INTERNAL_CHAT.THREAD.GO_BOTTOM_NEW', { count: newWhileAway })
          : t('INTERNAL_CHAT.THREAD.GO_BOTTOM')
      "
      @click="goToBottom"
    >
      <span class="flex-shrink-0 i-lucide-arrow-down size-5" />
      <span
        v-if="newWhileAway"
        class="absolute -top-1.5 -right-1.5 inline-flex items-center justify-center min-w-[20px] h-5 px-1 text-[11px] font-bold text-white rounded-full bg-n-teal-10 dark:bg-n-teal-5"
      >
        {{ newWhileAway > 99 ? '99+' : newWhileAway }}
      </span>
    </button>
  </div>
</template>
