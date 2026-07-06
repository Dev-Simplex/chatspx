<script setup>
// Chat interno — REDESIGN visual ligado ao BACKEND real (store internalChat).
// Mostra DMs, grupos e "grupos de time" (auto-criados a partir dos Teams da
// conta). Admin pode alternar "Ver todos" para auditar todos os canais.
// Envio de texto + emoji nesta versão; anexos/reações/respostas são próximos passos.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { messageStamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import getUuid from 'widget/helpers/uuid';
import ChatSidebar from '../components/redesign/ChatSidebar.vue';
import ChatHeader from '../components/redesign/ChatHeader.vue';
import MessageThread from '../components/redesign/MessageThread.vue';
import ChatComposer from '../components/redesign/ChatComposer.vue';
import ChatInfoPanel from '../components/redesign/ChatInfoPanel.vue';

const store = useStore();
const globalConfig = useMapGetter('globalConfig/get');
const channels = useMapGetter('internalChat/getChannels');
const auditChannels = useMapGetter('internalChat/getAuditChannels');
const agents = useMapGetter('internalChat/getAgents');
const uiFlags = useMapGetter('internalChat/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');
const currentRole = useMapGetter('getCurrentRole');
const allTeams = useMapGetter('teams/getTeams');
const myTeams = useMapGetter('teams/getMyTeams');

const isAdmin = computed(() => currentRole.value === 'administrator');
// Times que viram atalho de "grupo de time": admin vê todos; agente vê os seus.
const teamList = computed(() =>
  isAdmin.value ? allTeams.value : myTeams.value
);
// Auditoria (admin): a lista passa a mostrar TODOS os canais da conta.
const auditMode = ref(false);
// Canais abertos direto (ex.: grupo de time que um admin não-membro abriu pela
// aba "Grupos de time") — não vêm na lista escopada do fetchChannels.
const extraChannels = ref([]);
const rawChannelList = computed(() => {
  const base = auditMode.value ? auditChannels.value : channels.value;
  const ids = new Set(base.map(c => c.id));
  return [...extraChannels.value.filter(c => !ids.has(c.id)), ...base];
});

const activeId = ref(null);
const mobileView = ref('list'); // 'list' | 'thread' (só no mobile)
const searchOpen = ref(false);
const searchQuery = ref('');
const showInfo = ref(false);
// Favoritos: só do lado do cliente (o backend ainda não persiste favoritos).
const favorites = ref(new Set());

// Tela vazia (nenhuma conversa aberta): logo da marca + botão "Nova conversa".
const chatSidebarRef = ref(null);
const logoVisible = ref(true);
const brandLogo = computed(
  () =>
    globalConfig.value?.logoThumbnail ||
    globalConfig.value?.logo ||
    '/brand-assets/logo_thumbnail.svg'
);
const openNewConversation = () => chatSidebarRef.value?.openCompose();

const presenceOf = userId =>
  store.getters['agents/getAgentById'](userId)?.availability_status || null;
const counterpart = ch =>
  (ch?.members || []).find(m => m.id !== currentUserId.value);

const rowTime = ts => {
  if (!ts) return '';
  const d = new Date(ts * 1000);
  const now = new Date();
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString()) return messageStamp(ts, 'HH:mm');
  if (d.toDateString() === yesterday.toDateString()) return 'Ontem';
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};

const previewOf = ch => {
  const lm = ch?.last_message;
  if (!lm) return '';
  if (lm.deleted) return 'Mensagem apagada';
  return lm.content || '📎 Anexo';
};

// Traduz o canal do store para a forma que os componentes do redesign esperam.
const mapChannel = ch => {
  const isDm = ch.channel_type === 'direct';
  const other = isDm ? counterpart(ch) : null;
  const isMember = (ch.members || []).some(m => m.id === currentUserId.value);
  return {
    id: ch.id,
    channelType: ch.channel_type,
    name: isDm ? other?.name || ch.title || 'Conversa' : ch.title || 'Grupo',
    isGroup: !isDm,
    isTeam: ch.channel_type === 'team',
    avatarSrc: isDm ? other?.avatar_url || '' : '',
    iconName: isDm ? null : 'i-lucide-users',
    presence: isDm ? presenceOf(other?.id) : null,
    time: rowTime(ch.last_message?.created_at),
    unreadCount: ch.unread_count || 0,
    favorited: favorites.value.has(ch.id),
    lastMessage: {
      preview: previewOf(ch),
      fromMe: ch.last_message?.user?.id === currentUserId.value,
    },
    // cada membro carrega sua presença (online/busy/offline) do store de agentes
    members: (ch.members || []).map(m => ({
      ...m,
      presence: presenceOf(m.id),
    })),
    // Somente-leitura quando o usuário não é membro do canal (auditoria admin
    // ou grupo de time aberto por um admin que não está na equipe).
    readOnly: !isMember,
  };
};

const conversationList = computed(() => rawChannelList.value.map(mapChannel));

const activeRaw = computed(
  () =>
    channels.value.find(c => c.id === activeId.value) ||
    auditChannels.value.find(c => c.id === activeId.value) ||
    extraChannels.value.find(c => c.id === activeId.value)
);
const activeConversation = computed(() =>
  activeRaw.value ? mapChannel(activeRaw.value) : null
);

// ── Mensagens ──────────────────────────────────────────────────────────────
// "Limpar conversa": esconde as mensagens anteriores ao clique (só na MINHA
// visão; nada é apagado no servidor, recarregar restaura). channelId -> unix ts.
const clearedAt = ref({});
const rawMessages = computed(() => {
  const id = activeId.value;
  if (!id) return [];
  const msgs = store.getters['internalChat/getMessages'](id) || [];
  const cut = clearedAt.value[id];
  return cut ? msgs.filter(m => (m.created_at || 0) > cut) : msgs;
});
const dayKey = ts => new Date(ts * 1000).toDateString();
const dayLabelFor = ts => {
  const d = new Date(ts * 1000);
  const now = new Date();
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString()) return 'Hoje';
  if (d.toDateString() === yesterday.toDateString()) return 'Ontem';
  return d.toLocaleDateString('pt-BR');
};
const threadItems = computed(() => {
  const out = [];
  let lastDay = null;
  rawMessages.value.forEach(m => {
    const key = dayKey(m.created_at);
    if (key !== lastDay) {
      out.push({
        type: 'day',
        id: `day-${key}`,
        label: dayLabelFor(m.created_at),
      });
      lastDay = key;
    }
    out.push({
      type: 'message',
      id: m.id ?? m.echo_id,
      mine: m.user?.id === currentUserId.value,
      senderName: m.user?.name,
      avatarSrc: m.user?.avatar_url,
      content: m.deleted ? 'Mensagem apagada' : m.content,
      time: messageStamp(m.created_at, 'HH:mm'),
      read: m.status !== 'progress',
    });
  });
  return out;
});
const visibleMessages = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  if (!searchOpen.value || !q) return threadItems.value;
  return threadItems.value.filter(
    m => m.type === 'message' && (m.content || '').toLowerCase().includes(q)
  );
});

// ── Mídia e documentos da conversa (anexos das mensagens carregadas) ─────────
const IMAGE_RE = /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i;
const threadAttachments = computed(() => {
  const out = [];
  rawMessages.value.forEach(m =>
    (m.attachments || []).forEach(a => out.push(a))
  );
  return out;
});
const mediaItems = computed(() =>
  threadAttachments.value.filter(a => IMAGE_RE.test(a.filename || ''))
);
const docItems = computed(() =>
  threadAttachments.value.filter(a => !IMAGE_RE.test(a.filename || ''))
);

// ── Handlers ─────────────────────────────────────────────────────────────
const onSelect = async id => {
  activeId.value = id;
  mobileView.value = 'thread';
  searchOpen.value = false;
  searchQuery.value = '';
  showInfo.value = false;
  await store.dispatch('internalChat/fetchMessages', id);
};

const onSend = content => {
  const text = (content || '').trim();
  if (!text || !activeId.value) return;
  store.dispatch('internalChat/sendMessage', {
    channelId: activeId.value,
    content: text,
    echoId: getUuid(),
  });
};

const onCreateDm = async agentId => {
  const channel = await store.dispatch('internalChat/createDm', agentId);
  if (channel?.id) onSelect(channel.id);
};

const onCreateGroup = async ({ name, memberIds }) => {
  const channel = await store.dispatch('internalChat/createGroup', {
    name,
    memberIds,
  });
  if (channel?.id) onSelect(channel.id);
};

// Abre o "grupo de time" pronto: se já existe (membro), só abre; senão cria
// (admin). Casa pelo título do canal (= nome do time) já que o grupo é auto-criado.
const onCreateTeam = async team => {
  const existing = [
    ...channels.value,
    ...auditChannels.value,
    ...extraChannels.value,
  ].find(c => c.channel_type === 'team' && c.title === team.name);
  if (existing) {
    onSelect(existing.id);
    return;
  }
  const channel = await store.dispatch(
    'internalChat/createTeamChannel',
    team.id
  );
  if (channel?.id) {
    // guarda o canal aberto (o fetchChannels pode não trazê-lo se não sou membro)
    if (!extraChannels.value.some(c => c.id === channel.id)) {
      extraChannels.value = [...extraChannels.value, channel];
    }
    onSelect(channel.id);
  }
};

const onFavorite = () => {
  const id = activeId.value;
  if (id == null) return;
  const next = new Set(favorites.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  favorites.value = next;
};

const onLeave = async () => {
  const id = activeId.value;
  if (id == null) return;
  await store.dispatch('internalChat/leaveChannel', id);
  activeId.value = null;
  mobileView.value = 'list';
};

// "Limpar conversa" pede confirmação antes de esconder as mensagens.
const showClearConfirm = ref(false);
const onClear = () => {
  if (activeId.value == null) return;
  showClearConfirm.value = true;
};
const confirmClear = () => {
  const id = activeId.value;
  showClearConfirm.value = false;
  if (id == null) return;
  clearedAt.value = { ...clearedAt.value, [id]: Math.floor(Date.now() / 1000) };
};

const toggleSearch = () => {
  searchOpen.value = !searchOpen.value;
  if (!searchOpen.value) searchQuery.value = '';
};

const toggleAudit = async () => {
  auditMode.value = !auditMode.value;
  if (auditMode.value) await store.dispatch('internalChat/fetchAuditChannels');
};

// ── Ciclo de vida + tempo real ─────────────────────────────────────────────
const resync = () => {
  store.dispatch('internalChat/fetchChannels');
  if (auditMode.value) store.dispatch('internalChat/fetchAuditChannels');
};
onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, resync);
});
onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, resync);
  store.dispatch('internalChat/clearActiveChannel');
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex w-full h-full bg-n-background">
    <!-- Sidebar -->
    <div
      class="w-full h-full md:w-[360px] md:flex-shrink-0 md:border-r md:border-n-weak"
      :class="mobileView === 'thread' ? 'hidden md:block' : 'block'"
    >
      <ChatSidebar
        ref="chatSidebarRef"
        :conversations="conversationList"
        :active-id="activeId"
        :agents="agents"
        :teams="teamList"
        :is-admin="isAdmin"
        :audit-mode="auditMode"
        :loading="uiFlags.isFetchingChannels"
        @select="onSelect"
        @create-dm="onCreateDm"
        @create-group="onCreateGroup"
        @create-team="onCreateTeam"
        @toggle-audit="toggleAudit"
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
          @leave="onLeave"
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

        <ChatComposer
          v-if="!activeConversation.readOnly"
          :key="`composer-${activeId}`"
          @send="onSend"
        />
        <div
          v-else
          class="px-4 py-3 text-xs text-center md:px-6 flex-shrink-0 text-n-slate-10 bg-n-alpha-1 border-t border-n-weak"
        >
          Modo auditoria — somente leitura (você não participa deste canal).
        </div>

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
              :current-user-id="currentUserId"
              :media="mediaItems"
              :docs="docItems"
              @close="showInfo = false"
            />
          </div>
        </template>
      </template>

      <div
        v-else
        class="relative flex flex-col items-center justify-center flex-1 w-full px-8 py-16 text-center"
      >
        <div class="flex flex-col items-center max-w-md">
          <div v-if="logoVisible" class="mb-8 animate-float-gentle">
            <img
              :src="brandLogo"
              alt=""
              class="size-20 drop-shadow-sm"
              @error="logoVisible = false"
            />
          </div>

          <h3 class="text-2xl font-semibold text-n-slate-12">Chat interno</h3>

          <p
            class="mt-3 text-sm leading-relaxed text-center text-n-slate-10 max-w-sm"
          >
            Converse com sua equipe em tempo real. Selecione uma conversa ao
            lado ou comece uma nova.
          </p>

          <button
            type="button"
            class="wa-empty-cta flex items-center gap-2 mt-8 px-6 h-10 rounded-full text-white font-medium text-sm transition-colors active:scale-[0.97]"
            @click="openNewConversation"
          >
            <span class="i-lucide-message-square-plus size-4" />
            Nova conversa
          </button>
        </div>

        <div
          class="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-1.5"
        >
          <span class="i-lucide-lock size-3 text-n-slate-9" />
          <span class="text-xs text-n-slate-9">
            Mensagens internas protegidas entre a sua equipe
          </span>
        </div>
      </div>
    </div>

    <!-- Confirmação: limpar conversa -->
    <div
      v-if="showClearConfirm"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="showClearConfirm = false"
    >
      <div
        class="w-full max-w-xs p-5 border shadow-xl rounded-2xl bg-n-solid-1 border-n-weak"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">Limpar conversa?</h3>
        <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
          Tem certeza que deseja limpar esta conversa? As mensagens somem da sua
          visão — nada é apagado para os outros participantes.
        </p>
        <div class="flex justify-end gap-2 mt-4">
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="showClearConfirm = false"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-semibold text-white rounded-lg bg-n-ruby-9 hover:bg-n-ruby-10"
            @click="confirmClear"
          >
            Limpar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.animate-float-gentle {
  animation: float-gentle 3s ease-in-out infinite;
}
@keyframes float-gentle {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(-8px);
  }
}
</style>
