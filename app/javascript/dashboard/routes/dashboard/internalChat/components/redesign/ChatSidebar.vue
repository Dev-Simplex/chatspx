<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ConversationListItem from './ConversationListItem.vue';
import NotificationSettings from './NotificationSettings.vue';
import { useEscClose } from './useEscClose';

const props = defineProps({
  conversations: { type: Array, default: () => [] },
  activeId: { type: [Number, String], default: null },
  agents: { type: Array, default: () => [] },
  teams: { type: Array, default: () => [] },
  isAdmin: { type: Boolean, default: false },
  auditMode: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  loadError: { type: Boolean, default: false },
  currentUserId: { type: [Number, String], default: null },
  // Colegas online agora (já sem o próprio usuário): faixa de atalho no topo.
  onlineAgents: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'select',
  'createDm',
  'createGroup',
  'createTeam',
  'toggleAudit',
  'retry',
  'openMessage',
]);

const { t } = useI18n();
const store = useStore();
const search = ref('');

// ── Busca de conteúdo (cross-channel via backend, min 2 chars, debounce) ─────
// O campo de busca continua filtrando os nomes localmente; além disso, quando o
// termo tem ≥2 chars, consulta o servidor por mensagens que contenham o texto.
const searchResults = useMapGetter('internalChat/getSearchResults');
const uiFlags = useMapGetter('internalChat/getUIFlags');
const showMessageResults = computed(() => search.value.trim().length >= 2);
// Entre a digitação e a resposta do servidor a lista diz "Buscando…" (antes
// mostrava "Nenhuma mensagem encontrada" e depois os resultados apareciam).
const searchPending = ref(false);
const isSearchingMessages = computed(
  () => searchPending.value || uiFlags.value.isSearching
);
let searchTimer = null;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  const q = search.value.trim();
  if (q.length < 2) {
    searchPending.value = false;
    store.dispatch('internalChat/searchMessages', '');
    return;
  }
  searchPending.value = true;
  searchTimer = setTimeout(() => {
    searchPending.value = false;
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
// Resultado de mensagem: abre a conversa JÁ na mensagem (o pai rola e destaca).
const openResult = result => {
  if (!result?.internal_channel_id) return;
  emit('openMessage', {
    channelId: result.internal_channel_id,
    messageId: result.id,
  });
};
const activeFilter = ref('all');
const showCompose = ref(false);
const showSettings = ref(false);
const composeMode = ref('dm'); // 'dm' | 'group'
const groupName = ref('');
const groupMemberIds = ref([]);
// Busca de pessoas dentro de "Nova conversa" (DM e grupo).
const peopleQuery = ref('');
const peopleSearchRef = ref(null);
const matchesName = (name, q) =>
  (name || '').toLowerCase().includes(q.trim().toLowerCase());
const composeAgents = computed(() =>
  props.agents.filter(a => matchesName(a.name, peopleQuery.value))
);
const composeTeams = computed(() =>
  props.teams.filter(team => matchesName(team.name, peopleQuery.value))
);

const FILTERS = computed(() => [
  { key: 'all', label: t('INTERNAL_CHAT.LIST.ALL') },
  { key: 'unread', label: t('INTERNAL_CHAT.LIST.UNREAD') },
  { key: 'favorites', label: t('INTERNAL_CHAT.LIST.FAVORITES') },
]);

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

// Busca na lista também acha PESSOAS com quem ainda não há conversa: um clique
// e a conversa começa (antes a tela dizia "Nenhuma mensagem encontrada").
const peopleResults = computed(() => {
  const q = search.value.trim();
  if (!q) return [];
  const withDm = new Set(
    props.conversations
      .filter(c => c.channelType === 'direct')
      .flatMap(c => (c.members || []).map(m => m.id))
  );
  return props.agents
    .filter(a => !withDm.has(a.id) && matchesName(a.name, q))
    .slice(0, 5);
});

// Lista vazia no filtro: diz por quê, conforme a aba.
const emptyFilterText = computed(() => {
  if (search.value.trim()) return t('INTERNAL_CHAT.NO_SEARCH_RESULTS');
  if (activeFilter.value === 'unread') return t('INTERNAL_CHAT.LIST.NO_UNREAD');
  return t('INTERNAL_CHAT.LIST.NO_FAVORITES');
});

// Quantidade por aba (mostrada ao lado do rótulo).
const counts = computed(() => ({
  all: props.conversations.length,
  unread: props.conversations.filter(c => c.unreadCount > 0).length,
  favorites: props.conversations.filter(c => c.favorited).length,
}));

// Seções da aba "Todas": favoritas no topo, depois o resto por recência.
const sections = computed(() => {
  if (search.value.trim()) {
    return [
      {
        key: 'list',
        title: t('INTERNAL_CHAT.LIST.SECTION_RECENT'),
        items: filtered.value,
      },
    ].filter(sec => sec.items.length);
  }
  if (activeFilter.value !== 'all') {
    return [{ key: 'list', title: '', items: filtered.value }];
  }
  const fav = filtered.value.filter(c => c.favorited);
  const rest = filtered.value.filter(c => !c.favorited);
  if (!fav.length) return [{ key: 'list', title: '', items: rest }];
  return [
    {
      key: 'fav',
      title: t('INTERNAL_CHAT.LIST.SECTION_FAVORITES'),
      items: fav,
    },
    {
      key: 'rest',
      title: t('INTERNAL_CHAT.LIST.SECTION_RECENT'),
      items: rest,
    },
  ].filter(sec => sec.items.length);
});

// Frase do topo: o que é novo, em linguagem de gente.
const summary = computed(() => {
  const n = counts.value.unread;
  if (!n) return '';
  return n === 1
    ? t('INTERNAL_CHAT.LIST.SUMMARY_UNREAD_ONE')
    : t('INTERNAL_CHAT.LIST.SUMMARY_UNREAD_MANY', { count: n });
});
const showOnlineStrip = computed(
  () =>
    props.onlineAgents.length > 0 &&
    activeFilter.value === 'all' &&
    !search.value.trim()
);

// Fechar o popover não perde o grupo que estava sendo montado (nome e marcados
// continuam ao reabrir); só zera depois de criar.
const openCompose = (mode = 'dm') => {
  showCompose.value = true;
  composeMode.value = mode;
  peopleQuery.value = '';
  // Já dá para digitar o nome da pessoa.
  nextTick(() => peopleSearchRef.value?.focus());
};
const setComposeMode = mode => {
  composeMode.value = mode;
  peopleQuery.value = '';
  nextTick(() => peopleSearchRef.value?.focus());
};
const closeCompose = () => {
  showCompose.value = false;
};

const startDm = agent => {
  closeCompose();
  emit('createDm', agent.id);
};

// Enter na busca de pessoas: com um único nome na lista, já abre a conversa.
const onPeopleEnter = () => {
  if (composeMode.value === 'dm' && composeAgents.value.length === 1) {
    startDm(composeAgents.value[0]);
  }
};

const toggleGroupMember = id => {
  const i = groupMemberIds.value.indexOf(id);
  if (i === -1) groupMemberIds.value.push(id);
  else groupMemberIds.value.splice(i, 1);
  // Marcou alguém achado pela busca: limpa e volta o cursor para a próxima.
  if (peopleQuery.value) {
    peopleQuery.value = '';
    nextTick(() => peopleSearchRef.value?.focus());
  }
};

const canCreateGroup = computed(
  () => groupName.value.trim().length > 0 && groupMemberIds.value.length > 0
);
// Diz o que falta em vez de só apagar o botão.
const groupMissing = computed(() => {
  if (!groupMemberIds.value.length)
    return t('INTERNAL_CHAT.LIST.GROUP_NEEDS_PEOPLE');
  if (!groupName.value.trim()) return t('INTERNAL_CHAT.LIST.GROUP_NEEDS_NAME');
  return '';
});
const createGroup = () => {
  if (!canCreateGroup.value) return;
  emit('createGroup', {
    name: groupName.value.trim(),
    memberIds: [...groupMemberIds.value],
  });
  groupName.value = '';
  groupMemberIds.value = [];
  closeCompose();
};

// Abre (ou cria, se admin) o grupo pronto de um time.
const startTeam = team => {
  closeCompose();
  emit('createTeam', team);
};

useEscClose(showCompose, closeCompose);
useEscClose(showSettings, () => {
  showSettings.value = false;
});
// Esc na busca com texto: limpa (sem texto, deixa o Esc seguir para a tela).
const onSearchEsc = event => {
  if (!search.value) return;
  event.stopPropagation();
  search.value = '';
  onSearchInput();
};

// Permite que a tela vazia (no painel principal) abra o compose desta sidebar.
// Alt+B (atalho do pai) põe o cursor na busca.
const searchInputRef = ref(null);
const focusSearch = () => {
  searchInputRef.value?.focus();
  searchInputRef.value?.select();
};
defineExpose({ openCompose, focusSearch });
</script>

<template>
  <aside class="flex flex-col h-full bg-n-solid-1">
    <!-- Cabeçalho: título grande + o que é novo, como no app Mensagens -->
    <header
      class="flex flex-wrap items-center justify-between px-4 pt-5 pb-3 flex-shrink-0"
    >
      <div class="min-w-0">
        <h1
          class="text-[26px] font-bold leading-tight tracking-tight text-n-slate-12"
        >
          {{ t('INTERNAL_CHAT.TITLE') }}
        </h1>
      </div>
      <div class="relative flex items-center gap-1">
        <!-- Configurações de notificação -->
        <div>
          <button
            v-tooltip="t('INTERNAL_CHAT.NOTIFICATIONS.TITLE')"
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full size-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :class="showSettings ? 'text-n-teal-11 bg-n-alpha-2' : ''"
            :aria-label="t('INTERNAL_CHAT.NOTIFICATIONS.TITLE')"
            @click="showSettings = !showSettings"
          >
            <span class="text-lg i-lucide-bell" />
          </button>
          <template v-if="showSettings">
            <div class="fixed inset-0 z-10" @click="showSettings = false" />
            <div
              role="dialog"
              :aria-label="t('INTERNAL_CHAT.NOTIFICATIONS.TITLE')"
              class="absolute right-0 z-20 mt-2 overflow-hidden border shadow-xl top-full w-72 rounded-2xl bg-n-solid-1 border-n-weak"
            >
              <div class="flex items-center justify-between gap-2 px-4 pt-3">
                <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('INTERNAL_CHAT.NOTIFICATIONS.TITLE') }}
                </h3>
                <button
                  v-tooltip="t('INTERNAL_CHAT.CLOSE')"
                  type="button"
                  class="inline-flex items-center justify-center -me-2 rounded-full size-7 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  :aria-label="t('INTERNAL_CHAT.CLOSE')"
                  @click="showSettings = false"
                >
                  <span class="flex-shrink-0 text-base i-lucide-x" />
                </button>
              </div>
              <NotificationSettings />
            </div>
          </template>
        </div>
        <!-- Nova conversa -->
        <div>
          <button
            v-tooltip="t('INTERNAL_CHAT.EMPTY_STATE.NEW_SHORTCUT')"
            type="button"
            class="inline-flex items-center justify-center text-white transition-colors rounded-full shadow-sm size-9 bg-n-teal-10 dark:bg-n-teal-5 hover:bg-n-teal-11 dark:hover:bg-n-teal-6"
            :aria-label="t('INTERNAL_CHAT.EMPTY_STATE.NEW')"
            @click="showCompose ? closeCompose() : openCompose()"
          >
            <span class="text-lg i-lucide-square-pen" />
          </button>
          <template v-if="showCompose">
            <div class="fixed inset-0 z-10" @click="closeCompose" />
            <div
              role="dialog"
              :aria-label="t('INTERNAL_CHAT.EMPTY_STATE.NEW')"
              class="absolute right-0 z-20 mt-2 overflow-hidden border shadow-xl top-full w-72 rounded-2xl bg-n-solid-1 border-n-weak"
            >
              <div class="flex items-center justify-between gap-2 px-4 pt-3">
                <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
                  {{ t('INTERNAL_CHAT.EMPTY_STATE.NEW') }}
                </h3>
                <button
                  v-tooltip="t('INTERNAL_CHAT.CLOSE')"
                  type="button"
                  class="inline-flex items-center justify-center -me-2 rounded-full size-7 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  :aria-label="t('INTERNAL_CHAT.CLOSE')"
                  @click="closeCompose"
                >
                  <span class="flex-shrink-0 text-base i-lucide-x" />
                </button>
              </div>
              <!-- mode switch -->
              <div
                class="flex items-center gap-0.5 p-1 m-2 rounded-xl bg-n-alpha-2"
              >
                <button
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-xs font-semibold leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'dm'
                      ? 'bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="setComposeMode('dm')"
                >
                  {{ t('INTERNAL_CHAT.LIST.TAB_PERSON') }}
                </button>
                <button
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-xs font-semibold leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'group'
                      ? 'bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="setComposeMode('group')"
                >
                  {{ t('INTERNAL_CHAT.NEW_GROUP') }}
                </button>
                <button
                  v-if="teams.length"
                  type="button"
                  class="flex-1 px-1.5 py-1.5 text-xs font-semibold leading-tight rounded-lg transition-colors"
                  :class="
                    composeMode === 'team'
                      ? 'bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="setComposeMode('team')"
                >
                  {{ t('INTERNAL_CHAT.LIST.TAB_TEAMS') }}
                </button>
              </div>

              <!-- Busca de pessoas (DM e grupo): digitar o nome é o caminho -->
              <div class="px-2 pb-1">
                <div class="relative">
                  <span
                    class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
                  />
                  <input
                    ref="peopleSearchRef"
                    v-model="peopleQuery"
                    type="text"
                    :placeholder="
                      composeMode === 'team'
                        ? t('INTERNAL_CHAT.LIST.TEAM_SEARCH')
                        : t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')
                    "
                    :aria-label="
                      composeMode === 'team'
                        ? t('INTERNAL_CHAT.LIST.TEAM_SEARCH')
                        : t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')
                    "
                    class="reset-base w-full h-9 pl-9 pr-3 text-sm border rounded-xl outline-none bg-n-alpha-1 border-transparent focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
                    @keydown.enter.prevent="onPeopleEnter"
                  />
                </div>
              </div>

              <!-- DM: pick an agent -->
              <div
                v-if="composeMode === 'dm'"
                class="py-1 overflow-y-auto max-h-72"
              >
                <p class="mb-0 px-3 pt-1 pb-1 text-[11px] text-n-slate-10">
                  {{ t('INTERNAL_CHAT.LIST.PICK_PERSON') }}
                </p>
                <p
                  v-if="!composeAgents.length"
                  class="mb-0 px-3 py-4 text-xs text-center text-n-slate-10"
                >
                  {{
                    agents.length
                      ? t('INTERNAL_CHAT.LIST.NO_PEOPLE_MATCH')
                      : t('INTERNAL_CHAT.NO_AGENTS')
                  }}
                </p>
                <button
                  v-for="a in composeAgents"
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
                  <span
                    class="text-sm truncate text-n-slate-12"
                    :title="a.name"
                  >
                    {{ a.name }}
                  </span>
                </button>
              </div>

              <!-- Group: members (com busca acima) + name -->
              <div v-else-if="composeMode === 'group'" class="px-2 pb-2">
                <p
                  class="flex items-center justify-between mb-0 px-1 pt-1 pb-1 text-[11px] text-n-slate-10"
                >
                  <span>{{ t('INTERNAL_CHAT.LIST.PICK_MEMBERS') }}</span>
                  <span
                    v-if="groupMemberIds.length"
                    class="font-semibold text-n-teal-11"
                  >
                    {{
                      t('INTERNAL_CHAT.LIST.SELECTED_COUNT', {
                        count: groupMemberIds.length,
                      })
                    }}
                  </span>
                </p>
                <div class="py-1 overflow-y-auto max-h-44">
                  <p
                    v-if="!composeAgents.length"
                    class="mb-0 px-3 py-3 text-xs text-center text-n-slate-10"
                  >
                    {{ t('INTERNAL_CHAT.LIST.NO_PEOPLE_MATCH') }}
                  </p>
                  <label
                    v-for="a in composeAgents"
                    :key="a.id"
                    class="flex items-center w-full gap-2.5 px-2 py-1.5 text-left rounded-lg cursor-pointer hover:bg-n-alpha-1"
                  >
                    <input
                      type="checkbox"
                      class="accent-n-teal-10"
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
                <label
                  class="block px-1 pt-2 pb-1 text-[11px] font-semibold text-n-slate-11"
                  for="internal-chat-group-name"
                >
                  {{ t('INTERNAL_CHAT.GROUP_NAME') }}
                </label>
                <input
                  id="internal-chat-group-name"
                  v-model="groupName"
                  type="text"
                  :placeholder="t('INTERNAL_CHAT.GROUP_NAME_PLACEHOLDER')"
                  class="reset-base w-full h-9 px-3 text-sm border rounded-xl outline-none bg-n-alpha-1 border-transparent focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
                  @keydown.enter.prevent="createGroup"
                />
                <button
                  type="button"
                  class="w-full px-3 py-2 mt-2 text-sm font-semibold text-white rounded-xl bg-n-teal-10 dark:bg-n-teal-5 hover:bg-n-teal-11 disabled:opacity-40"
                  :disabled="!canCreateGroup"
                  @click="createGroup"
                >
                  {{
                    groupMemberIds.length
                      ? t('INTERNAL_CHAT.LIST.CREATE_GROUP_WITH', {
                          count: groupMemberIds.length,
                        })
                      : t('INTERNAL_CHAT.LIST.CREATE_GROUP')
                  }}
                </button>
                <p
                  v-if="groupMissing"
                  class="mb-0 px-1 pt-1.5 text-[11px] text-center text-n-slate-10"
                >
                  {{ groupMissing }}
                </p>
              </div>

              <!-- Grupos de time: um clique abre o grupo pronto do time -->
              <div v-else class="py-1 overflow-y-auto max-h-72">
                <p class="mb-0 px-3 pt-1 pb-1 text-[11px] text-n-slate-10">
                  {{ t('INTERNAL_CHAT.LIST.TEAMS_HINT') }}
                </p>
                <p
                  v-if="!composeTeams.length"
                  class="mb-0 px-3 py-4 text-xs text-center text-n-slate-10"
                >
                  {{ t('INTERNAL_CHAT.LIST.NO_TEAM_MATCH') }}
                </p>
                <button
                  v-for="team in composeTeams"
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
      <p
        v-if="summary"
        class="flex items-center gap-1.5 mt-0.5 mb-0 text-[13px] basis-full text-n-teal-11 font-semibold"
      >
        <span class="flex-shrink-0 size-3.5 i-lucide-message-circle-more" />
        {{ summary }}
      </p>
    </header>

    <!-- Busca arredondada -->
    <div class="px-4 pb-3 flex-shrink-0">
      <div class="relative">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
        />
        <input
          ref="searchInputRef"
          v-model="search"
          type="text"
          :placeholder="t('INTERNAL_CHAT.LIST.SEARCH_PLACEHOLDER')"
          :aria-label="t('INTERNAL_CHAT.LIST.SEARCH_PLACEHOLDER')"
          class="reset-base w-full h-9 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-full bg-n-alpha-2 focus:border-n-teal-9 focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10"
          @input="onSearchInput"
          @keydown.esc="onSearchEsc"
        />
      </div>
    </div>

    <!-- Admin: ver todos os canais (auditoria) -->
    <div v-if="isAdmin" class="px-4 pb-3 flex-shrink-0">
      <button
        v-tooltip="t('INTERNAL_CHAT.AUDIT.HINT')"
        type="button"
        class="flex items-center justify-between w-full gap-2 px-3 py-1.5 text-xs font-medium transition-colors border rounded-full"
        :class="
          auditMode
            ? 'text-n-teal-11 border-n-teal-9 bg-n-alpha-1'
            : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'
        "
        @click="$emit('toggleAudit')"
      >
        <span class="flex items-center gap-2">
          <span class="text-sm i-lucide-shield" />
          {{ t('INTERNAL_CHAT.AUDIT.OFF') }}
        </span>
        <span
          class="relative inline-flex items-center flex-shrink-0 h-5 transition-colors rounded-full w-9"
          :class="auditMode ? 'bg-n-teal-9' : 'bg-n-slate-6'"
        >
          <span
            class="inline-block w-4 h-4 transition-transform bg-white rounded-full shadow"
            :class="auditMode ? 'translate-x-4' : 'translate-x-0.5'"
          />
        </span>
      </button>
    </div>

    <!-- Filtro em controle segmentado (cabe em 1 linha até 1024 px) -->
    <div class="px-4 pb-2 flex-shrink-0">
      <div
        role="tablist"
        :aria-label="t('INTERNAL_CHAT.LIST.FILTERS')"
        class="flex items-center gap-0.5 p-0.5 rounded-xl bg-n-alpha-2"
      >
        <button
          v-for="f in FILTERS"
          :key="f.key"
          type="button"
          role="tab"
          :aria-selected="activeFilter === f.key"
          class="flex items-center justify-center flex-1 min-w-0 gap-1 px-1.5 py-1.5 text-[13px] font-semibold whitespace-nowrap transition-all duration-200 rounded-[10px]"
          :class="
            activeFilter === f.key
              ? 'bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeFilter = f.key"
        >
          <span class="truncate">{{ f.label }}</span>
          <span
            v-if="counts[f.key]"
            class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-bold flex-shrink-0"
            :class="
              f.key === 'unread'
                ? 'bg-n-teal-10 dark:bg-n-teal-5 text-white'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            {{ counts[f.key] }}
          </span>
        </button>
      </div>
    </div>

    <!-- Online agora: um clique e já está conversando -->
    <div v-if="showOnlineStrip" class="pt-1 pb-1 flex-shrink-0">
      <p
        class="mb-0 px-4 pb-1 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
      >
        {{ t('INTERNAL_CHAT.LIST.ONLINE_NOW') }}
      </p>
      <div class="flex gap-0.5 px-2 overflow-x-auto [scrollbar-width:none]">
        <button
          v-for="a in onlineAgents"
          :key="a.id"
          v-tooltip="`${a.name} · ${t('INTERNAL_CHAT.LIST.ONLINE_NOW_HINT')}`"
          type="button"
          class="flex flex-col items-center flex-shrink-0 w-16 gap-1 px-1 py-1.5 transition-colors rounded-xl hover:bg-n-alpha-1"
          @click="startDm(a)"
        >
          <Avatar
            :name="a.name"
            :src="a.avatar_url || a.thumbnail || ''"
            :size="40"
            status="online"
            rounded-full
          />
          <span class="w-full text-[11px] text-center truncate text-n-slate-11">
            {{ (a.name || '').split(' ')[0] }}
          </span>
        </button>
      </div>
    </div>

    <!-- Conversation list -->
    <div
      class="flex-1 min-h-0 px-2 pt-1 pb-3 overflow-y-auto border-t border-n-weak"
    >
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
      <!-- Falhou ao carregar: diz e oferece tentar de novo -->
      <div
        v-else-if="loadError && !conversations.length"
        class="flex flex-col items-center gap-3 px-4 py-10 text-center"
      >
        <span class="text-2xl i-lucide-wifi-off text-n-ruby-11" />
        <p class="mb-0 text-sm text-n-slate-12">
          {{ t('INTERNAL_CHAT.LOAD_ERROR') }}
        </p>
        <button
          type="button"
          class="px-4 py-1.5 text-xs font-semibold rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
          @click="emit('retry')"
        >
          {{ t('INTERNAL_CHAT.RETRY') }}
        </button>
      </div>
      <!-- Ninguém conversou ainda: diz o que fazer -->
      <div
        v-else-if="!conversations.length && !search.trim()"
        class="flex flex-col items-center gap-3 px-6 py-10 text-center"
      >
        <span class="text-3xl i-lucide-messages-square text-n-slate-9" />
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.LIST.EMPTY_TITLE') }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('INTERNAL_CHAT.LIST.EMPTY_HINT') }}
        </p>
        <button
          type="button"
          class="flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-white rounded-full bg-n-teal-10 dark:bg-n-teal-5 hover:bg-n-teal-11"
          @click="openCompose()"
        >
          <span class="i-lucide-square-pen" />
          {{ t('INTERNAL_CHAT.EMPTY_STATE.NEW') }}
        </button>
      </div>
      <template v-else>
        <section v-for="sec in sections" :key="sec.key">
          <p
            v-if="sec.title"
            class="mb-0 px-4 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
          >
            {{ sec.title }}
          </p>
          <div v-for="(c, i) in sec.items" :key="c.id" class="relative">
            <ConversationListItem
              :conversation="c"
              :active="c.id === activeId"
              :current-user-id="currentUserId"
              @select="$emit('select', $event)"
            />
            <!-- separador fino, recuado depois do avatar (como no iPhone) -->
            <span
              v-if="i < sec.items.length - 1"
              class="absolute bottom-0 right-3 left-[76px] h-px bg-n-weak"
            />
          </div>
        </section>
        <!-- Pessoas sem conversa ainda: um clique começa a conversa -->
        <template v-if="peopleResults.length">
          <p
            class="mb-0 px-4 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.LIST.SECTION_PEOPLE') }}
          </p>
          <button
            v-for="a in peopleResults"
            :key="`person-${a.id}`"
            type="button"
            class="flex items-center w-full gap-3 py-2 pl-4 pr-3 text-left transition-colors rounded-2xl hover:bg-n-alpha-1"
            @click="startDm(a)"
          >
            <Avatar
              :name="a.name"
              :src="a.avatar_url || a.thumbnail || ''"
              :size="40"
              :status="a.availability_status === 'online' ? 'online' : null"
              rounded-full
            />
            <span class="flex-1 min-w-0">
              <span
                class="block text-sm font-semibold truncate text-n-slate-12"
              >
                {{ a.name }}
              </span>
              <span class="block text-xs text-n-teal-11">
                {{ t('INTERNAL_CHAT.LIST.START_CHAT') }}
              </span>
            </span>
            <span
              class="flex-shrink-0 i-lucide-message-circle-plus size-4 text-n-slate-10"
            />
          </button>
        </template>
        <p
          v-if="
            !filtered.length && !showMessageResults && !peopleResults.length
          "
          class="mb-0 px-4 py-10 text-sm text-center text-n-slate-10"
        >
          {{ emptyFilterText }}
        </p>

        <!-- Resultados de mensagens (busca por conteúdo, cross-channel) -->
        <template v-if="showMessageResults">
          <p
            class="mb-0 px-4 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.LIST.MESSAGES') }}
          </p>
          <button
            v-for="r in isSearchingMessages ? [] : searchResults"
            :key="`msg-${r.id}`"
            type="button"
            class="flex flex-col w-full gap-0.5 px-4 py-2 text-left rounded-2xl hover:bg-n-alpha-1 transition-colors"
            @click="openResult(r)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12 truncate">
                <span class="font-normal text-n-slate-10">
                  {{ t('INTERNAL_CHAT.LIST.IN_CONVERSATION') }}
                </span>
                {{ r.channel_title }}
              </span>
              <span class="text-[11px] text-n-slate-10 flex-shrink-0">
                {{ resultTime(r.created_at) }}
              </span>
            </span>
            <span class="block text-xs truncate text-n-slate-10">
              <span class="text-n-slate-11">{{ r.user?.name }}:</span>
              {{ r.content || `📎 ${t('INTERNAL_CHAT.ATTACHMENT')}` }}
            </span>
          </button>
          <p
            v-if="isSearchingMessages"
            class="flex items-center justify-center gap-2 px-4 py-6 mb-0 text-sm text-n-slate-11"
          >
            <span class="i-lucide-loader-circle animate-spin" />
            {{ t('INTERNAL_CHAT.SEARCHING') }}
          </p>
          <p
            v-else-if="!searchResults.length"
            class="mb-0 px-4 py-6 text-sm text-center text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.NO_RESULTS') }}
          </p>
        </template>
      </template>
    </div>
  </aside>
</template>
