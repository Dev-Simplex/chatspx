<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ConversationListItem from './ConversationListItem.vue';
import NotificationSettings from './NotificationSettings.vue';

const props = defineProps({
  conversations: { type: Array, default: () => [] },
  activeId: { type: [Number, String], default: null },
  agents: { type: Array, default: () => [] },
  teams: { type: Array, default: () => [] },
  isAdmin: { type: Boolean, default: false },
  auditMode: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits([
  'select',
  'createDm',
  'createGroup',
  'createTeam',
  'toggleAudit',
  'openMentions',
]);

const store = useStore();
const search = ref('');

// ── Busca de conteúdo (cross-channel via backend, min 2 chars, debounce) ─────
// O campo de busca continua filtrando os nomes localmente; além disso, quando o
// termo tem ≥2 chars, consulta o servidor por mensagens que contenham o texto.
const searchResults = useMapGetter('internalChat/getSearchResults');
const showMessageResults = computed(() => search.value.trim().length >= 2);
let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  const q = search.value.trim();
  if (q.length < 2) {
    store.dispatch('internalChat/searchMessages', '');
    return;
  }
  searchTimer = setTimeout(() => {
    store.dispatch('internalChat/searchMessages', q);
  }, 300);
};
const resultTime = ts => {
  if (!ts) return '';
  return new Date(ts * 1000).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
const openResult = result => {
  if (result?.internal_channel_id) emit('select', result.internal_channel_id);
};
const activeFilter = ref('all');
const showCompose = ref(false);
const showSettings = ref(false);
const composeMode = ref('dm'); // 'dm' | 'group'
const groupName = ref('');
const groupMemberIds = ref([]);

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
  return list;
});

// Quantidade por aba (mostrada ao lado do rótulo).
const counts = computed(() => ({
  all: props.conversations.length,
  unread: props.conversations.filter(c => c.unreadCount > 0).length,
  favorites: props.conversations.filter(c => c.favorited).length,
}));

const openCompose = () => {
  showCompose.value = true;
  composeMode.value = 'dm';
  groupName.value = '';
  groupMemberIds.value = [];
};
const closeCompose = () => {
  showCompose.value = false;
};

const startDm = agent => {
  closeCompose();
  emit('createDm', agent.id);
};

const toggleGroupMember = id => {
  const i = groupMemberIds.value.indexOf(id);
  if (i === -1) groupMemberIds.value.push(id);
  else groupMemberIds.value.splice(i, 1);
};

const canCreateGroup = computed(
  () => groupName.value.trim().length > 0 && groupMemberIds.value.length > 0
);
const createGroup = () => {
  if (!canCreateGroup.value) return;
  emit('createGroup', {
    name: groupName.value.trim(),
    memberIds: [...groupMemberIds.value],
  });
  closeCompose();
};

// Abre (ou cria, se admin) o grupo pronto de um time.
const startTeam = team => {
  closeCompose();
  emit('createTeam', team);
};

// Permite que a tela vazia (no painel principal) abra o compose desta sidebar.
defineExpose({ openCompose });
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <aside class="flex flex-col h-full bg-n-solid-1">
    <!-- Header -->
    <header
      class="flex items-center justify-between px-4 pt-4 pb-2 flex-shrink-0"
    >
      <h1 class="text-lg font-bold text-n-slate-12">Chat Interno</h1>
      <div class="flex items-center gap-0.5">
        <!-- Inbox de menções -->
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          title="Menções"
          @click="$emit('openMentions')"
        >
          <span class="text-lg i-lucide-at-sign" />
        </button>
        <!-- Configurações de notificação -->
        <div class="relative">
          <button
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :class="showSettings ? 'text-n-brand bg-n-alpha-2' : ''"
            title="Notificações"
            @click="showSettings = !showSettings"
          >
            <span class="text-lg i-lucide-bell" />
          </button>
          <template v-if="showSettings">
            <div class="fixed inset-0 z-10" @click="showSettings = false" />
            <div
              class="absolute right-0 z-20 mt-1 overflow-hidden border shadow-lg top-full w-72 rounded-xl bg-n-solid-1 border-n-weak"
            >
              <NotificationSettings />
            </div>
          </template>
        </div>
        <!-- Nova conversa -->
        <div class="relative">
          <button
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :class="showCompose ? 'text-n-brand bg-n-alpha-2' : ''"
            title="Nova conversa"
            @click="showCompose ? closeCompose() : openCompose()"
          >
            <span class="text-lg i-lucide-square-pen" />
          </button>
          <template v-if="showCompose">
            <div class="fixed inset-0 z-10" @click="closeCompose" />
            <div
              class="absolute right-0 z-20 mt-1 overflow-hidden border shadow-lg top-full w-72 rounded-xl bg-n-solid-1 border-n-weak"
            >
              <!-- mode switch -->
              <div class="flex items-center gap-1 p-1 border-b border-n-weak">
                <button
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-[11px] font-medium leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'dm'
                      ? 'bg-n-alpha-2 text-n-brand'
                      : 'text-n-slate-11 hover:bg-n-alpha-1'
                  "
                  @click="composeMode = 'dm'"
                >
                  Conversa
                </button>
                <button
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-[11px] font-medium leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'group'
                      ? 'bg-n-alpha-2 text-n-brand'
                      : 'text-n-slate-11 hover:bg-n-alpha-1'
                  "
                  @click="composeMode = 'group'"
                >
                  Novo grupo
                </button>
                <button
                  v-if="teams.length"
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-[11px] font-medium leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'team'
                      ? 'bg-n-alpha-2 text-n-brand'
                      : 'text-n-slate-11 hover:bg-n-alpha-1'
                  "
                  @click="composeMode = 'team'"
                >
                  Grupos de time
                </button>
              </div>

              <!-- DM: pick an agent -->
              <div
                v-if="composeMode === 'dm'"
                class="py-1 overflow-y-auto max-h-72"
              >
                <p
                  v-if="!agents.length"
                  class="px-3 py-4 text-xs text-center text-n-slate-10"
                >
                  Nenhum colega disponível.
                </p>
                <button
                  v-for="a in agents"
                  :key="a.id"
                  type="button"
                  class="flex items-center w-full gap-2.5 px-3 py-2 text-left hover:bg-n-alpha-1"
                  @click="startDm(a)"
                >
                  <Avatar
                    :name="a.name"
                    :src="a.avatar_url || a.thumbnail || ''"
                    :size="30"
                    :status="
                      a.availability_status === 'online' ? 'online' : null
                    "
                    rounded-full
                  />
                  <span class="text-sm text-n-slate-12">{{ a.name }}</span>
                </button>
              </div>

              <!-- Group: name + members -->
              <div v-else-if="composeMode === 'group'" class="p-2">
                <input
                  v-model="groupName"
                  type="text"
                  placeholder="Nome do grupo"
                  class="reset-base w-full h-9 px-3 mb-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12 placeholder:text-n-slate-10"
                />
                <div class="py-1 overflow-y-auto max-h-52">
                  <label
                    v-for="a in agents"
                    :key="a.id"
                    class="flex items-center w-full gap-2.5 px-2 py-1.5 text-left rounded-lg cursor-pointer hover:bg-n-alpha-1"
                  >
                    <input
                      type="checkbox"
                      class="accent-n-brand"
                      :checked="groupMemberIds.includes(a.id)"
                      @change="toggleGroupMember(a.id)"
                    />
                    <Avatar
                      :name="a.name"
                      :src="a.avatar_url || ''"
                      :size="26"
                      rounded-full
                    />
                    <span class="text-sm text-n-slate-12">{{ a.name }}</span>
                  </label>
                </div>
                <button
                  type="button"
                  class="w-full px-3 py-2 mt-1 text-xs font-semibold text-white rounded-lg bg-n-brand hover:bg-n-brand-hover disabled:opacity-40"
                  :disabled="!canCreateGroup"
                  @click="createGroup"
                >
                  Criar grupo
                </button>
              </div>

              <!-- Grupos de time: um clique abre o grupo pronto do time -->
              <div v-else class="py-1 overflow-y-auto max-h-72">
                <p class="px-3 pt-2 pb-1 text-[11px] text-n-slate-10">
                  Grupos que espelham suas equipes (membros = time).
                </p>
                <button
                  v-for="team in teams"
                  :key="team.id"
                  type="button"
                  class="flex items-center w-full gap-2.5 px-3 py-2 text-left hover:bg-n-alpha-1"
                  @click="startTeam(team)"
                >
                  <span
                    class="inline-flex items-center justify-center flex-shrink-0 rounded-full w-7 h-7 bg-n-alpha-2 text-n-slate-11"
                  >
                    <span class="text-sm i-lucide-users" />
                  </span>
                  <span class="text-sm capitalize text-n-slate-12">
                    {{ team.name }}
                  </span>
                </button>
              </div>
            </div>
          </template>
        </div>
      </div>
    </header>

    <!-- Search -->
    <div class="px-4 pb-2 flex-shrink-0">
      <div class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="search"
          type="text"
          placeholder="Buscar conversas e mensagens..."
          class="reset-base w-full h-10 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-brand focus:bg-n-background text-n-slate-12 placeholder:text-n-slate-10"
          @input="onSearchInput"
        />
      </div>
    </div>

    <!-- Admin: ver todos os canais (auditoria) -->
    <div v-if="isAdmin" class="px-4 pb-2 flex-shrink-0">
      <button
        type="button"
        class="flex items-center justify-between w-full gap-2 px-3 py-2 text-xs font-medium transition-colors border rounded-xl"
        :class="
          auditMode
            ? 'text-n-brand border-n-brand bg-n-alpha-2'
            : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
        "
        title="Ver todos os canais da conta (somente leitura nos que você não participa)"
        @click="$emit('toggleAudit')"
      >
        <span class="flex items-center gap-2">
          <span class="text-sm i-lucide-shield" />
          Ver todos os canais (admin)
        </span>
        <span
          class="relative inline-flex items-center flex-shrink-0 h-5 transition-colors rounded-full w-9"
          :class="auditMode ? 'bg-n-brand' : 'bg-n-slate-4'"
        >
          <span
            class="inline-block w-4 h-4 transition-transform bg-white rounded-full shadow"
            :class="auditMode ? 'translate-x-4' : 'translate-x-0.5'"
          />
        </span>
      </button>
    </div>

    <!-- Filter tabs -->
    <div
      class="flex items-center gap-1 px-4 border-b border-n-weak flex-shrink-0"
    >
      <button
        v-for="f in FILTERS"
        :key="f.key"
        type="button"
        class="relative inline-flex items-center gap-1.5 px-2 pb-2.5 pt-1 text-sm font-medium transition-colors"
        :class="
          activeFilter === f.key
            ? 'text-n-brand'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeFilter = f.key"
      >
        {{ f.label }}
        <span
          class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-semibold"
          :class="
            activeFilter === f.key
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{ counts[f.key] }}
        </span>
        <span
          v-if="activeFilter === f.key"
          class="absolute inset-x-2 -bottom-px h-0.5 rounded-full bg-n-brand"
        />
      </button>
    </div>

    <!-- Conversation list -->
    <div class="flex-1 min-h-0 px-2 py-2 space-y-0.5 overflow-y-auto">
      <template v-if="loading && !conversations.length">
        <div
          v-for="n in 6"
          :key="n"
          class="flex items-center gap-3 px-3 py-2.5 animate-pulse"
        >
          <span class="w-11 h-11 rounded-full bg-n-alpha-2" />
          <span class="flex-1 space-y-2">
            <span class="block w-1/2 h-3 rounded bg-n-alpha-2" />
            <span class="block w-3/4 h-2.5 rounded bg-n-alpha-1" />
          </span>
        </div>
      </template>
      <template v-else>
        <ConversationListItem
          v-for="c in filtered"
          :key="c.id"
          :conversation="c"
          :active="c.id === activeId"
          @select="$emit('select', $event)"
        />
        <p
          v-if="!filtered.length && !showMessageResults"
          class="px-4 py-10 text-sm text-center text-n-slate-10"
        >
          Nenhuma conversa encontrada.
        </p>

        <!-- Resultados de mensagens (busca por conteúdo, cross-channel) -->
        <template v-if="showMessageResults">
          <p
            class="px-3 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
          >
            Mensagens
          </p>
          <button
            v-for="r in searchResults"
            :key="`msg-${r.id}`"
            type="button"
            class="flex flex-col w-full gap-0.5 px-3 py-2 text-left rounded-xl hover:bg-n-alpha-1 transition-colors"
            @click="openResult(r)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12 truncate">
                {{ r.channel_title }}
              </span>
              <span class="text-[11px] text-n-slate-10 flex-shrink-0">
                {{ resultTime(r.created_at) }}
              </span>
            </span>
            <span class="block text-xs truncate text-n-slate-10">
              <span class="text-n-slate-11">{{ r.user?.name }}:</span>
              {{ r.content || '📎 Anexo' }}
            </span>
          </button>
          <p
            v-if="!searchResults.length"
            class="px-4 py-6 text-sm text-center text-n-slate-10"
          >
            Nenhuma mensagem encontrada.
          </p>
        </template>
      </template>
    </div>
  </aside>
</template>
