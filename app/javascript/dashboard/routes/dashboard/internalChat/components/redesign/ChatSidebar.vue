<script setup>
import { ref, computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ConversationListItem from './ConversationListItem.vue';
import { availableContacts } from './mockData.js';

const props = defineProps({
  conversations: { type: Array, default: () => [] },
  activeId: { type: [Number, String], default: null },
});

const emit = defineEmits(['select', 'create']);

const search = ref('');
const activeFilter = ref('all');
const sortMode = ref('recent');
const showCompose = ref(false);
const showSort = ref(false);

const FILTERS = [
  { key: 'all', label: 'Todas' },
  { key: 'unread', label: 'Não lidas' },
  { key: 'favorites', label: 'Favoritas' },
];

const filtered = computed(() => {
  let list = props.conversations;
  if (activeFilter.value === 'unread') {
    list = list.filter(c => c.unreadCount > 0);
  } else if (activeFilter.value === 'favorites') {
    list = list.filter(c => c.favorited);
  }
  const q = search.value.trim().toLowerCase();
  if (q) list = list.filter(c => c.name.toLowerCase().includes(q));
  if (sortMode.value === 'unread') {
    list = [...list].sort(
      (a, b) => (b.unreadCount || 0) - (a.unreadCount || 0)
    );
  }
  return list;
});

const createWith = contact => {
  showCompose.value = false;
  emit('create', contact);
};
</script>

<template>
  <!-- Protótipo visual (dados fictícios); i18n entra na versão final. -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <aside class="flex flex-col h-full bg-n-solid-1">
    <!-- Header -->
    <header
      class="flex items-center justify-between px-4 pt-4 pb-2 flex-shrink-0"
    >
      <h1 class="text-lg font-bold text-n-slate-12">Chat Interno</h1>
      <div class="relative">
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showCompose ? 'text-n-brand bg-n-alpha-2' : ''"
          title="Nova conversa"
          @click="showCompose = !showCompose"
        >
          <span class="text-lg i-lucide-square-pen" />
        </button>
        <template v-if="showCompose">
          <div class="fixed inset-0 z-10" @click="showCompose = false" />
          <div
            class="absolute right-0 z-20 mt-1 overflow-hidden border shadow-lg top-full w-64 rounded-xl bg-n-solid-1 border-n-weak"
          >
            <p
              class="px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              Iniciar conversa com
            </p>
            <button
              v-for="c in availableContacts"
              :key="c.id"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-left hover:bg-n-alpha-1"
              @click="createWith(c)"
            >
              <Avatar
                :name="c.name"
                :size="30"
                :status="c.presence === 'online' ? 'online' : null"
                rounded-full
              />
              <span class="text-sm text-n-slate-12">{{ c.name }}</span>
            </button>
          </div>
        </template>
      </div>
    </header>

    <!-- Search + sort -->
    <div class="flex items-center gap-2 px-4 pb-2 flex-shrink-0">
      <div class="relative flex-1">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="search"
          type="text"
          placeholder="Buscar conversas..."
          class="reset-base w-full h-10 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-brand focus:bg-n-background text-n-slate-12 placeholder:text-n-slate-10"
        />
      </div>
      <div class="relative flex-shrink-0">
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-xl w-10 h-10 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showSort ? 'text-n-brand bg-n-alpha-2' : ''"
          title="Ordenar"
          @click="showSort = !showSort"
        >
          <span class="text-lg i-lucide-sliders-horizontal" />
        </button>
        <template v-if="showSort">
          <div class="fixed inset-0 z-10" @click="showSort = false" />
          <div
            class="absolute right-0 z-20 py-1 mt-1 overflow-hidden border shadow-lg top-full w-52 rounded-xl bg-n-solid-1 border-n-weak"
          >
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="(sortMode = 'recent'), (showSort = false)"
            >
              Mais recentes
              <span
                v-if="sortMode === 'recent'"
                class="i-lucide-check text-n-brand"
              />
            </button>
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="(sortMode = 'unread'), (showSort = false)"
            >
              Não lidas primeiro
              <span
                v-if="sortMode === 'unread'"
                class="i-lucide-check text-n-brand"
              />
            </button>
          </div>
        </template>
      </div>
    </div>

    <!-- Filter tabs -->
    <div
      class="flex items-center gap-1 px-4 border-b border-n-weak flex-shrink-0"
    >
      <button
        v-for="f in FILTERS"
        :key="f.key"
        type="button"
        class="relative px-2 pb-2.5 pt-1 text-sm font-medium transition-colors"
        :class="
          activeFilter === f.key
            ? 'text-n-brand'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeFilter = f.key"
      >
        {{ f.label }}
        <span
          v-if="activeFilter === f.key"
          class="absolute inset-x-2 -bottom-px h-0.5 rounded-full bg-n-brand"
        />
      </button>
    </div>

    <!-- Conversation list -->
    <div class="flex-1 min-h-0 px-2 py-2 space-y-0.5 overflow-y-auto">
      <ConversationListItem
        v-for="c in filtered"
        :key="c.id"
        :conversation="c"
        :active="c.id === activeId"
        @select="$emit('select', $event)"
      />
      <p
        v-if="!filtered.length"
        class="px-4 py-10 text-sm text-center text-n-slate-10"
      >
        Nenhuma conversa encontrada.
      </p>
    </div>
  </aside>
</template>
