<script setup>
// Chat interno — REDESIGN visual (protótipo, dados fictícios). Toda a lógica é
// mock (client-side); os componentes são reutilizáveis para plugar o backend
// real depois. NÃO usa o store.
import { ref, computed } from 'vue';
import ChatSidebar from '../components/redesign/ChatSidebar.vue';
import ChatHeader from '../components/redesign/ChatHeader.vue';
import MessageThread from '../components/redesign/MessageThread.vue';
import ChatComposer from '../components/redesign/ChatComposer.vue';
import ChatInfoPanel from '../components/redesign/ChatInfoPanel.vue';
import { conversations, getThread } from '../components/redesign/mockData.js';

const conversationList = ref(conversations.map(c => ({ ...c })));
const activeId = ref(conversationList.value[0]?.id ?? null);
// Cada conversa tem sua própria thread (limpar/enviar afetam só a conversa atual).
const threadsById = ref({});
const ensureThread = id => {
  if (id != null && !threadsById.value[id]) {
    threadsById.value[id] = [...getThread(id)];
  }
};
ensureThread(activeId.value);

const mobileView = ref('list'); // 'list' | 'thread' (só no mobile)
const searchOpen = ref(false);
const searchQuery = ref('');
const showInfo = ref(false);
let localSeq = 0;
let newConvSeq = 0;

const activeConversation = computed(() =>
  conversationList.value.find(c => c.id === activeId.value)
);

const messages = computed(() => threadsById.value[activeId.value] || []);

const visibleMessages = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  if (!searchOpen.value || !q) return messages.value;
  return messages.value.filter(
    m => m.type === 'message' && (m.content || '').toLowerCase().includes(q)
  );
});

const onSelect = id => {
  ensureThread(id);
  activeId.value = id;
  mobileView.value = 'thread';
  searchOpen.value = false;
  searchQuery.value = '';
  showInfo.value = false;
  // Abrir uma conversa "zera" o contador de não lidas.
  const conv = conversationList.value.find(c => c.id === id);
  if (conv) conv.unreadCount = 0;
};

const onSend = content => {
  localSeq += 1;
  const id = activeId.value;
  ensureThread(id);
  threadsById.value[id].push({
    type: 'message',
    id: `local-${localSeq}`,
    mine: true,
    content,
    time: 'agora',
    read: false,
  });
  const conv = activeConversation.value;
  if (conv) {
    conv.lastMessage = { preview: content, fromMe: true };
    conv.time = 'agora';
  }
};

const onCreate = contact => {
  // Se já existe uma DM com essa pessoa, apenas abre; senão cria e abre.
  const existing = conversationList.value.find(
    c => !c.isGroup && c.name === contact.name
  );
  if (existing) {
    onSelect(existing.id);
    return;
  }
  newConvSeq += 1;
  const id = `new-${newConvSeq}`;
  conversationList.value.unshift({
    id,
    name: contact.name,
    isGroup: false,
    avatarSrc: null,
    presence: contact.presence,
    time: 'agora',
    unreadCount: 0,
    favorited: false,
    lastMessage: { preview: 'Diga olá 👋', fromMe: false },
  });
  onSelect(id);
};

const onFavorite = () => {
  const conv = activeConversation.value;
  if (conv) conv.favorited = !conv.favorited;
};

const onMarkUnread = () => {
  const conv = activeConversation.value;
  if (conv) conv.unreadCount = Math.max(conv.unreadCount, 1);
};

const onClear = () => {
  // Limpa APENAS a conversa aberta (as demais threads ficam intactas).
  threadsById.value[activeId.value] = [
    { type: 'day', id: 'd0', label: 'Hoje' },
  ];
  const conv = activeConversation.value;
  if (conv) conv.lastMessage = { preview: 'Conversa limpa', fromMe: false };
};

const toggleSearch = () => {
  searchOpen.value = !searchOpen.value;
  if (!searchOpen.value) searchQuery.value = '';
};
</script>

<template>
  <!-- Protótipo visual (dados fictícios); i18n entra na versão final. -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex w-full h-full bg-n-background">
    <!-- Sidebar -->
    <div
      class="w-full h-full md:w-[360px] md:flex-shrink-0 md:border-r md:border-n-weak"
      :class="mobileView === 'thread' ? 'hidden md:block' : 'block'"
    >
      <ChatSidebar
        :conversations="conversationList"
        :active-id="activeId"
        @select="onSelect"
        @create="onCreate"
      />
    </div>

    <!-- Conversation -->
    <div
      class="relative flex-col flex-1 h-full min-w-0"
      :class="mobileView === 'thread' ? 'flex' : 'hidden md:flex'"
    >
      <template v-if="activeConversation">
        <ChatHeader
          :conversation="activeConversation"
          :search-active="searchOpen"
          :info-active="showInfo"
          @back="mobileView = 'list'"
          @toggle-search="toggleSearch"
          @toggle-info="showInfo = !showInfo"
          @favorite="onFavorite"
          @mark-unread="onMarkUnread"
          @clear="onClear"
        />

        <!-- In-conversation search bar -->
        <div
          v-if="searchOpen"
          class="flex items-center gap-2 px-4 py-2 border-b md:px-6 border-n-weak bg-n-background flex-shrink-0"
        >
          <div class="relative flex-1">
            <span
              class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Buscar nesta conversa..."
              class="reset-base w-full h-9 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-brand focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10"
            />
          </div>
          <button
            type="button"
            class="inline-flex items-center justify-center rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2"
            title="Fechar busca"
            @click="toggleSearch"
          >
            <span class="text-lg i-lucide-x" />
          </button>
        </div>

        <!-- key por conversa: remonta → fade da thread + rola pro fim ao abrir -->
        <MessageThread :key="activeId" :items="visibleMessages" />
        <!-- key por conversa: rascunho/anexos não vazam ao trocar de conversa -->
        <ChatComposer :key="activeId" @send="onSend" />

        <!-- Info drawer -->
        <template v-if="showInfo">
          <div
            class="absolute inset-0 z-20 md:hidden bg-n-alpha-black2"
            @click="showInfo = false"
          />
          <div
            class="absolute inset-y-0 right-0 z-30 w-80 max-w-[85%] border-l shadow-xl border-n-weak"
          >
            <ChatInfoPanel
              :conversation="activeConversation"
              @close="showInfo = false"
            />
          </div>
        </template>
      </template>

      <div
        v-else
        class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
      >
        <span class="text-4xl opacity-60 i-lucide-messages-square" />
        <p class="text-sm">Selecione uma conversa para começar.</p>
      </div>
    </div>
  </div>
</template>
