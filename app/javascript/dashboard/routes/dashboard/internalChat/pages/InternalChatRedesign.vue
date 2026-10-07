<script setup>
// Chat interno — tela viva, ligada ao store internalChat (backend real).
// Mostra DMs, grupos e "grupos de time" (auto-criados a partir dos Teams da
// conta). Admin pode alternar "Ver todos" para auditar todos os canais.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { messageStamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import getUuid from 'widget/helpers/uuid';
import ChatSidebar from '../components/redesign/ChatSidebar.vue';
import ChatHeader from '../components/redesign/ChatHeader.vue';
import MessageThread from '../components/redesign/MessageThread.vue';
import ChatComposer from '../components/redesign/ChatComposer.vue';
import ChatInfoPanel from '../components/redesign/ChatInfoPanel.vue';
import ManageChannelDialog from '../components/ManageChannelDialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const store = useStore();
const { t } = useI18n();
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
const showManage = ref(false);

// Silenciar: conversa silenciada não toca som nem mostra aviso (menção ainda
// avisa). Fica nas preferências do usuário; o Sidebar global respeita a lista.
const { uiSettings, updateUISettings } = useUISettings();
const mutedIds = computed(
  () => uiSettings.value?.internal_chat_muted_channel_ids || []
);
const onToggleMute = () => {
  const id = activeId.value;
  if (id == null) return;
  const next = mutedIds.value.includes(id)
    ? mutedIds.value.filter(x => x !== id)
    : [...mutedIds.value, id];
  updateUISettings({ internal_chat_muted_channel_ids: next });
};

// Preferências por navegador (favoritos e rascunhos): localStorage pode faltar
// (aba anônima, bloqueio) — a tela segue funcionando, só não lembra.
const readLocal = (key, fallback) => {
  try {
    return JSON.parse(localStorage.getItem(key)) ?? fallback;
  } catch (e) {
    return fallback;
  }
};
const writeLocal = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch (e) {
    // sem armazenamento: só não persiste
  }
};
const favoritesKey = computed(
  () => `internal_chat_favorites_${currentUserId.value}`
);
const favorites = ref(new Set(readLocal(favoritesKey.value, [])));
const DRAFTS_KEY = 'internal_chat_drafts';
const drafts = ref(readLocal(DRAFTS_KEY, {}));
const onDraftChange = text => {
  const id = activeId.value;
  if (id == null) return;
  const next = { ...drafts.value };
  if (text) next[id] = text;
  else delete next[id];
  drafts.value = next;
  writeLocal(DRAFTS_KEY, next);
};

// Tela inicial (nenhuma conversa aberta): "Comece por aqui".
const chatSidebarRef = ref(null);
const currentUser = useMapGetter('getCurrentUser');
const openNewConversation = () => chatSidebarRef.value?.openCompose();

const presenceOf = userId =>
  store.getters['agents/getAgentById'](userId)?.availability_status || null;
const counterpart = ch =>
  (ch?.members || []).find(m => m.id !== currentUserId.value);

const isSameDay = (a, b) => a.toDateString() === b.toDateString();
const yesterdayDate = () => {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return d;
};

const rowTime = ts => {
  if (!ts) return '';
  const d = new Date(ts * 1000);
  if (isSameDay(d, new Date())) return messageStamp(ts, 'HH:mm');
  if (isSameDay(d, yesterdayDate())) return t('INTERNAL_CHAT.YESTERDAY');
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};

const previewOf = ch => {
  const lm = ch?.last_message;
  if (!lm) return '';
  if (lm.deleted) return t('INTERNAL_CHAT.DELETED');
  return lm.content || `📎 ${t('INTERNAL_CHAT.ATTACHMENT')}`;
};

// Traduz o canal do store para a forma que os componentes do redesign esperam.
const mapChannel = ch => {
  const isDm = ch.channel_type === 'direct';
  const other = isDm ? counterpart(ch) : null;
  const isMember = (ch.members || []).some(m => m.id === currentUserId.value);
  const lm = ch.last_message;
  return {
    id: ch.id,
    channelType: ch.channel_type,
    name: isDm
      ? other?.name || ch.title || t('INTERNAL_CHAT.DIRECT')
      : ch.title || t('INTERNAL_CHAT.HEADER.GROUP'),
    isGroup: !isDm,
    isTeam: ch.channel_type === 'team',
    avatarSrc: isDm ? other?.avatar_url || '' : '',
    iconName: isDm ? null : 'i-lucide-users',
    presence: isDm ? presenceOf(other?.id) : null,
    time: rowTime(lm?.created_at),
    lastAt: lm?.created_at || 0,
    unreadCount: ch.unread_count || 0,
    favorited: favorites.value.has(ch.id),
    muted: mutedIds.value.includes(ch.id),
    lastMessage: {
      preview: previewOf(ch),
      fromMe: Boolean(lm) && lm.user_id === currentUserId.value,
      // Em grupo, a prévia diz quem escreveu (primeiro nome).
      author: !isDm && lm?.user_name ? lm.user_name.split(' ')[0] : '',
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

// Mais recente no topo (como em qualquer mensageiro); sem mensagem vai pro fim.
const conversationList = computed(() =>
  rawChannelList.value.map(mapChannel).sort((a, b) => b.lastAt - a.lastAt)
);

const activeRaw = computed(
  () =>
    channels.value.find(c => c.id === activeId.value) ||
    auditChannels.value.find(c => c.id === activeId.value) ||
    extraChannels.value.find(c => c.id === activeId.value)
);
const activeConversation = computed(() =>
  activeRaw.value ? mapChannel(activeRaw.value) : null
);
// Só grupo ad-hoc tem gerenciamento (time é dirigido pela equipe).
const canManage = computed(
  () =>
    activeConversation.value?.isGroup &&
    !activeConversation.value.isTeam &&
    !activeConversation.value.readOnly
);
// Quem pode ser @mencionado: os outros membros (só em grupo).
const mentionCandidates = computed(() => {
  const conv = activeConversation.value;
  if (!conv?.isGroup) return [];
  return conv.members.filter(m => m.id !== currentUserId.value);
});

// Colegas online agora (sem você): atalho na lista e na tela inicial.
const onlineAgents = computed(() =>
  (agents.value || []).filter(
    a =>
      a.id !== currentUserId.value &&
      (presenceOf(a.id) || a.availability_status) === 'online'
  )
);
const greeting = computed(() => {
  const h = new Date().getHours();
  const name = (currentUser.value?.name || '').split(' ')[0];
  if (h < 12) return t('INTERNAL_CHAT.HOME.GREETING_MORNING', { name });
  if (h < 18) return t('INTERNAL_CHAT.HOME.GREETING_AFTERNOON', { name });
  return t('INTERNAL_CHAT.HOME.GREETING_EVENING', { name });
});
const unreadConversations = computed(() =>
  conversationList.value.filter(c => c.unreadCount > 0)
);
const homeSummary = computed(() => {
  const n = unreadConversations.value.length;
  if (!n) return t('INTERNAL_CHAT.HOME.ALL_READ');
  return n === 1
    ? t('INTERNAL_CHAT.HOME.UNREAD_ONE')
    : t('INTERNAL_CHAT.HOME.UNREAD_MANY', { count: n });
});
const HOME_PEOPLE = 8;

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
const hasMore = computed(() =>
  activeId.value
    ? store.getters['internalChat/getHasMore'](activeId.value)
    : false
);
const loadingMessages = ref(false);
const loadingOlder = ref(false);

const dayLabelFor = ts => {
  const d = new Date(ts * 1000);
  if (isSameDay(d, new Date())) return t('INTERNAL_CHAT.TODAY');
  if (isSameDay(d, yesterdayDate())) return t('INTERNAL_CHAT.YESTERDAY');
  return d.toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
  });
};

// ✓✓ só quando é verdade: em DM, o colega leu até depois desta mensagem.
const counterpartReadAt = computed(() => {
  const conv = activeConversation.value;
  if (!conv || conv.isGroup) return null;
  return counterpart(activeRaw.value)?.last_read_at || null;
});
const deliveryOf = m => {
  if (m.status === 'progress') return 'progress';
  if (m.status === 'failed') return 'failed';
  const readAt = counterpartReadAt.value;
  return readAt && readAt >= m.created_at ? 'read' : 'sent';
};

const GROUP_WINDOW = 5 * 60; // mensagens seguidas do mesmo autor em 5 min
const STAMP_GAP = 30 * 60; // pausa maior que isso ganha horário centralizado
// Onde começam as mensagens novas da conversa aberta (capturado ao abrir,
// antes de o selo de não lidas zerar): { channelId, count }.
const unreadOnOpen = ref(null);
const threadItems = computed(() => {
  const out = [];
  const isGroup = Boolean(activeConversation.value?.isGroup);
  const msgs = rawMessages.value;
  const me = currentUserId.value;

  // A 1ª das N últimas mensagens de outras pessoas recebe "Mensagens novas".
  let newFromId = null;
  const marker = unreadOnOpen.value;
  if (marker && marker.channelId === activeId.value && marker.count > 0) {
    let left = marker.count;
    for (let i = msgs.length - 1; i >= 0 && left > 0; i -= 1) {
      if (msgs[i].user?.id !== me && !msgs[i].deleted) {
        left -= 1;
        if (left === 0) newFromId = msgs[i].id;
      }
    }
  }
  // "Entregue/Lida" só embaixo da minha última mensagem (como no iPhone).
  const lastMine = [...msgs]
    .reverse()
    .find(m => m.user?.id === me && m.status !== 'failed');

  let prev = null;
  msgs.forEach(m => {
    if (
      !prev ||
      !isSameDay(
        new Date(prev.created_at * 1000),
        new Date(m.created_at * 1000)
      ) ||
      m.created_at - prev.created_at > STAMP_GAP
    ) {
      out.push({
        type: 'stamp',
        id: `stamp-${m.id ?? m.echo_id}`,
        day: dayLabelFor(m.created_at),
        time: messageStamp(m.created_at, 'HH:mm'),
      });
      prev = null;
    }
    if (newFromId != null && m.id === newFromId) {
      out.push({ type: 'new', id: 'new-messages' });
      prev = null;
    }
    const mine = m.user?.id === me;
    const continued =
      Boolean(prev) &&
      prev.user?.id === m.user?.id &&
      m.created_at - prev.created_at < GROUP_WINDOW;
    let delivery = null;
    if (mine && (m.status === 'progress' || m.status === 'failed')) {
      delivery = deliveryOf(m);
    } else if (
      mine &&
      lastMine &&
      (m.id ?? m.echo_id) === (lastMine.id ?? lastMine.echo_id)
    ) {
      delivery = deliveryOf(m);
    }
    out.push({
      type: 'message',
      id: m.id ?? m.echo_id,
      echoId: m.echo_id,
      mine,
      userId: m.user?.id,
      senderName: m.user?.name,
      avatarSrc: m.user?.avatar_url,
      // Nome em cima só no 1º balão de uma sequência de outra pessoa, em grupo.
      showSender: isGroup && !mine && !continued,
      inGroup: isGroup,
      continued,
      tail: true, // recalculado abaixo: só o último da sequência tem cauda
      mentionsMe: (m.mentioned_user_ids || []).map(Number).includes(Number(me)),
      content: m.content,
      time: messageStamp(m.created_at, 'HH:mm'),
      delivery,
      // campos crus para render rico (anexos, reações, reply, editado, apagada…)
      attachments: m.attachments || [],
      reactions: m.reactions || {},
      replyTo: m.reply_to || null,
      sharedConversation: m.shared_conversation || null,
      edited: Boolean(m.edited),
      deleted: Boolean(m.deleted),
      status: m.status,
      uploadProgress: m.upload_progress ?? null,
      mentionedUserIds: m.mentioned_user_ids || [],
    });
    prev = m;
  });
  out.forEach((item, i) => {
    if (item.type !== 'message') return;
    const next = out[i + 1];
    item.tail = !(next?.type === 'message' && next.continued);
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
// Nomes que viram destaque de @menção no balão (agentes da conta).
const mentionNames = computed(() =>
  (agents.value || []).map(a => a.name).filter(Boolean)
);

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
// Mensagem sendo respondida (barra "respondendo a X" no composer). Fica no pai
// para que enviar/cancelar/trocar de conversa a limpem de forma consistente.
const replyingTo = ref(null);

const onSelect = async id => {
  activeId.value = id;
  mobileView.value = 'thread';
  searchOpen.value = false;
  searchQuery.value = '';
  showInfo.value = false;
  replyingTo.value = null;
  // Guarda quantas eram novas (para o divisor "Mensagens novas") e zera o selo
  // na hora; o servidor confirma no fetchMessages.
  const opened = rawChannelList.value.find(c => c.id === id);
  unreadOnOpen.value = { channelId: id, count: opened?.unread_count || 0 };
  store.commit('internalChat/CLEAR_UNREAD', id);
  loadingMessages.value = !store.getters['internalChat/getMessages'](id).length;
  try {
    await store.dispatch('internalChat/fetchMessages', id);
  } finally {
    if (activeId.value === id) loadingMessages.value = false;
  }
};

const onLoadOlder = async () => {
  const id = activeId.value;
  if (!id || loadingOlder.value || !hasMore.value) return;
  loadingOlder.value = true;
  try {
    await store.dispatch('internalChat/fetchOlderMessages', id);
  } finally {
    loadingOlder.value = false;
  }
};

// O composer emite { content, attachments, replyToId, mentionedUserIds }.
// Falha vira balão "não enviada · tentar de novo" (o store marca).
const onSend = ({
  content,
  attachments = [],
  replyToId = null,
  mentionedUserIds = [],
} = {}) => {
  const text = (content || '').trim();
  if ((!text && !attachments.length) || !activeId.value) return;
  store
    .dispatch('internalChat/sendMessage', {
      channelId: activeId.value,
      content: text,
      attachments,
      mentionedUserIds,
      replyToId: replyToId || replyingTo.value?.id || null,
      echoId: getUuid(),
    })
    .catch(() => {});
  replyingTo.value = null;
};

const onReply = msg => {
  replyingTo.value = {
    id: msg.id,
    name: msg.senderName,
    preview: msg.content || `📎 ${t('INTERNAL_CHAT.ATTACHMENT')}`,
  };
};
const onCancelReply = () => {
  replyingTo.value = null;
};

const onReact = ({ messageId, emoji }) => {
  if (!activeId.value) return;
  store.dispatch('internalChat/reactToMessage', {
    channelId: activeId.value,
    messageId,
    emoji,
  });
};

const onEdit = ({ messageId, content }) => {
  const text = (content || '').trim();
  if (!text || !activeId.value) return;
  store.dispatch('internalChat/editMessage', {
    channelId: activeId.value,
    messageId,
    content: text,
  });
};

const onDelete = messageId => {
  if (!activeId.value) return;
  store.dispatch('internalChat/deleteMessage', {
    channelId: activeId.value,
    messageId,
  });
};

// Reenvia uma bolha que falhou (reusa o echo_id para reconciliar no lugar).
const onRetry = msg => {
  if (!activeId.value) return;
  store
    .dispatch('internalChat/sendMessage', {
      channelId: activeId.value,
      content: msg.content,
      mentionedUserIds: msg.mentionedUserIds || [],
      echoId: msg.echoId || msg.id,
    })
    .catch(() => {});
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
  writeLocal(favoritesKey.value, [...next]);
};

const closeActive = () => {
  activeId.value = null;
  mobileView.value = 'list';
  showManage.value = false;
};

const onLeave = async () => {
  const id = activeId.value;
  if (id == null) return;
  await store.dispatch('internalChat/leaveChannel', id);
  closeActive();
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

// "Buscar" do painel de detalhes: abre a busca da conversa.
const onInfoSearch = () => {
  searchOpen.value = true;
  if (window.innerWidth < 1280) showInfo.value = false;
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
const resyncList = () => {
  store.dispatch('internalChat/fetchChannels');
  if (auditMode.value) store.dispatch('internalChat/fetchAuditChannels');
};
// Socket caiu e voltou: pode ter perdido mensagens da conversa aberta.
const onReconnect = () => {
  resyncList();
  if (activeId.value)
    store.dispatch('internalChat/fetchMessages', activeId.value);
};
// Voltou para a aba: lista atualizada e a conversa aberta conta como lida.
const onVisibility = () => {
  if (document.hidden) return;
  resyncList();
  if (activeId.value && !activeConversation.value?.readOnly) {
    store.dispatch('internalChat/markRead', activeId.value);
  }
};
onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
  document.addEventListener('visibilitychange', onVisibility);
});
onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
  document.removeEventListener('visibilitychange', onVisibility);
  store.dispatch('internalChat/clearActiveChannel');
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background">
    <!-- Sidebar -->
    <div
      class="relative w-full h-full md:w-[320px] xl:w-[380px] md:flex-shrink-0 md:border-r md:border-n-weak"
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
        :load-error="uiFlags.channelsLoadError"
        :current-user-id="currentUserId"
        :online-agents="onlineAgents"
        @select="onSelect"
        @create-dm="onCreateDm"
        @create-group="onCreateGroup"
        @create-team="onCreateTeam"
        @toggle-audit="toggleAudit"
        @retry="resyncList"
      />
    </div>

    <!-- Conversation -->
    <div
      class="relative flex-col flex-1 h-full min-w-0"
      :class="mobileView === 'thread' ? 'flex' : 'hidden md:flex'"
    >
      <div v-if="activeConversation" class="flex flex-1 min-h-0">
        <div class="relative flex flex-col flex-1 min-w-0">
          <ChatHeader
            :conversation="activeConversation"
            :search-active="searchOpen"
            :info-active="showInfo"
            :can-manage="canManage"
            @back="mobileView = 'list'"
            @toggle-search="toggleSearch"
            @toggle-info="showInfo = !showInfo"
            @show-members="showInfo = true"
            @manage="showManage = true"
            @toggle-mute="onToggleMute"
            @favorite="onFavorite"
            @leave="onLeave"
            @clear="onClear"
          />

          <!-- In-conversation search bar -->
          <div
            v-if="searchOpen"
            class="flex items-center gap-2 px-3 py-2 border-b md:px-5 border-n-weak bg-n-background flex-shrink-0"
          >
            <div class="relative flex-1">
              <span
                class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
              />
              <input
                v-model="searchQuery"
                type="text"
                :placeholder="t('INTERNAL_CHAT.THREAD.SEARCH_PLACEHOLDER')"
                class="reset-base w-full h-9 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-full bg-n-alpha-2 focus:border-n-teal-9 focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10"
              />
            </div>
            <button
              v-tooltip="t('INTERNAL_CHAT.THREAD.CLOSE_SEARCH')"
              type="button"
              class="inline-flex items-center justify-center rounded-full size-9 text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="t('INTERNAL_CHAT.THREAD.CLOSE_SEARCH')"
              @click="toggleSearch"
            >
              <span class="text-lg i-lucide-x" />
            </button>
          </div>

          <!-- key por conversa: remonta → fade da thread + rola pro fim ao abrir -->
          <MessageThread
            :key="activeId"
            :items="visibleMessages"
            :current-user-id="currentUserId"
            :loading="loadingMessages"
            :loading-older="loadingOlder"
            :has-more="hasMore && !(searchOpen && searchQuery.trim())"
            :searching="searchOpen && Boolean(searchQuery.trim())"
            :mention-names="mentionNames"
            @load-older="onLoadOlder"
            @react="onReact"
            @edit="onEdit"
            @delete="onDelete"
            @reply="onReply"
            @retry="onRetry"
          />

          <ChatComposer
            v-if="!activeConversation.readOnly"
            :key="`composer-${activeId}`"
            :replying-to="replyingTo"
            :initial-draft="drafts[activeId] || ''"
            :mention-candidates="mentionCandidates"
            @send="onSend"
            @draft-change="onDraftChange"
            @cancel-reply="onCancelReply"
          />
          <div
            v-else
            class="flex items-center justify-center gap-1.5 px-4 py-3 text-xs text-center md:px-6 flex-shrink-0 text-n-slate-11 bg-n-alpha-1 border-t border-n-weak"
          >
            <span class="i-lucide-eye size-4" />
            {{ t('INTERNAL_CHAT.AUDIT.READONLY_HINT') }}
          </div>
        </div>

        <!-- Detalhes: coluna ao lado a partir de 1280 px; gaveta por cima abaixo disso -->
        <template v-if="showInfo">
          <div
            class="absolute inset-0 z-20 xl:hidden bg-n-alpha-black2"
            @click="showInfo = false"
          />
          <div
            class="absolute inset-y-0 right-0 z-30 w-80 max-w-[85%] border-l shadow-xl xl:shadow-none xl:static xl:flex-shrink-0 border-n-weak"
          >
            <ChatInfoPanel
              :conversation="activeConversation"
              :current-user-id="currentUserId"
              :media="mediaItems"
              :docs="docItems"
              :can-manage="canManage"
              @manage="showManage = true"
              @search="onInfoSearch"
              @toggle-mute="onToggleMute"
              @favorite="onFavorite"
              @close="showInfo = false"
            />
          </div>
        </template>

        <ManageChannelDialog
          :show="showManage"
          :channel="activeRaw"
          @close="showManage = false"
          @left="closeActive"
        />
      </div>

      <!-- Tela inicial: "Comece por aqui" — o que é novo, quem está online,
           seus times e o que dá para fazer, tudo a um clique. -->
      <div v-else class="flex-1 min-h-0 overflow-y-auto">
        <div class="w-full max-w-2xl px-6 pt-12 pb-10 mx-auto">
          <h2 class="text-3xl font-bold tracking-tight text-n-slate-12">
            {{ greeting }}
          </h2>
          <p class="mb-0 mt-2 text-[15px] text-n-slate-11">
            {{ homeSummary }}
          </p>
          <div class="flex flex-wrap gap-2 mt-5">
            <button
              v-if="unreadConversations.length"
              type="button"
              class="inline-flex items-center gap-2 px-4 text-sm font-semibold text-white transition-colors rounded-full h-10 bg-n-teal-10 dark:bg-n-teal-5 hover:bg-n-teal-11"
              @click="onSelect(unreadConversations[0].id)"
            >
              <span class="i-lucide-message-circle-more size-4" />
              {{
                t('INTERNAL_CHAT.HOME.OPEN_LATEST', {
                  name: unreadConversations[0].name,
                })
              }}
            </button>
            <button
              type="button"
              class="inline-flex items-center gap-2 px-4 text-sm font-semibold transition-colors rounded-full h-10"
              :class="
                unreadConversations.length
                  ? 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3'
                  : 'bg-n-teal-10 dark:bg-n-teal-5 text-white hover:bg-n-teal-11'
              "
              @click="openNewConversation"
            >
              <span class="i-lucide-square-pen size-4" />
              {{ t('INTERNAL_CHAT.EMPTY_STATE.NEW') }}
            </button>
          </div>

          <!-- Colegas online agora -->
          <section
            class="p-5 mt-8 border rounded-3xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-baseline justify-between gap-3">
              <h3
                class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
              >
                <span class="rounded-full size-2 bg-n-teal-9" />
                {{ t('INTERNAL_CHAT.HOME.ONLINE_TITLE') }}
                <span class="font-normal text-n-slate-10">
                  {{ onlineAgents.length }}
                </span>
              </h3>
              <span class="text-xs text-n-slate-10">
                {{
                  onlineAgents.length ? t('INTERNAL_CHAT.HOME.ONLINE_HINT') : ''
                }}
              </span>
            </div>
            <p
              v-if="!onlineAgents.length"
              class="mb-0 mt-3 text-sm text-n-slate-11"
            >
              {{ t('INTERNAL_CHAT.HOME.NO_ONLINE') }}
            </p>
            <div v-else class="grid grid-cols-4 gap-1 mt-3 sm:grid-cols-8">
              <button
                v-for="a in onlineAgents.slice(0, HOME_PEOPLE)"
                :key="a.id"
                v-tooltip="a.name"
                type="button"
                class="flex flex-col items-center gap-1.5 px-1 py-2 transition-colors rounded-2xl hover:bg-n-alpha-1"
                @click="onCreateDm(a.id)"
              >
                <Avatar
                  :name="a.name"
                  :src="a.avatar_url || a.thumbnail || ''"
                  :size="48"
                  status="online"
                  rounded-full
                />
                <span
                  class="w-full text-xs text-center truncate text-n-slate-12"
                >
                  {{ (a.name || '').split(' ')[0] }}
                </span>
              </button>
            </div>
            <button
              v-if="onlineAgents.length > HOME_PEOPLE"
              type="button"
              class="mt-2 text-xs font-semibold text-n-teal-11 hover:underline"
              @click="openNewConversation"
            >
              {{
                t('INTERNAL_CHAT.HOME.MORE_PEOPLE', {
                  count: onlineAgents.length - HOME_PEOPLE,
                })
              }}
            </button>
          </section>

          <!-- Seus times -->
          <section
            v-if="teamList.length"
            class="p-5 mt-4 border rounded-3xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-baseline justify-between gap-3">
              <h3 class="text-sm font-semibold text-n-slate-12">
                {{ t('INTERNAL_CHAT.HOME.TEAMS_TITLE') }}
              </h3>
              <span class="text-xs text-n-slate-10">
                {{ t('INTERNAL_CHAT.HOME.TEAMS_HINT') }}
              </span>
            </div>
            <div class="flex flex-wrap gap-2 mt-3">
              <button
                v-for="team in teamList.slice(0, 8)"
                :key="team.id"
                type="button"
                class="inline-flex items-center gap-2 py-1.5 pl-1.5 pr-3.5 text-sm font-medium capitalize transition-colors rounded-full bg-n-alpha-1 hover:bg-n-alpha-2 text-n-slate-12"
                @click="onCreateTeam(team)"
              >
                <span
                  class="inline-flex items-center justify-center rounded-full size-7 bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-11"
                >
                  <span class="i-lucide-users size-4" />
                </span>
                {{ team.name }}
              </button>
            </div>
          </section>

          <!-- O que dá para fazer aqui -->
          <section
            class="p-5 mt-4 border rounded-3xl border-n-weak bg-n-solid-1"
          >
            <h3 class="text-sm font-semibold text-n-slate-12">
              {{ t('INTERNAL_CHAT.HOME.TIPS_TITLE') }}
            </h3>
            <ul class="grid gap-3 mt-3 sm:grid-cols-2">
              <li
                v-for="tip in [
                  ['i-lucide-at-sign', 'INTERNAL_CHAT.EMPTY_STATE.TIP_MENTION'],
                  [
                    'i-lucide-hash',
                    'INTERNAL_CHAT.EMPTY_STATE.TIP_CONVERSATION',
                  ],
                  ['i-lucide-share-2', 'INTERNAL_CHAT.EMPTY_STATE.TIP_SHARE'],
                  ['i-lucide-mic', 'INTERNAL_CHAT.HOME.TIP_AUDIO'],
                ]"
                :key="tip[1]"
                class="flex items-start gap-3 text-[13px] leading-snug text-n-slate-11"
              >
                <span
                  class="inline-flex items-center justify-center flex-shrink-0 rounded-xl size-8 bg-n-teal-9/15 text-n-teal-11"
                >
                  <span class="size-4" :class="tip[0]" />
                </span>
                <span class="pt-1.5">{{ t(tip[1]) }}</span>
              </li>
            </ul>
          </section>

          <p
            class="mb-0 flex items-center justify-center gap-1.5 mt-8 text-xs text-n-slate-10"
          >
            <span class="i-lucide-lock size-3" />
            {{ t('INTERNAL_CHAT.EMPTY_STATE.PRIVATE') }}
          </p>
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
        class="w-full max-w-xs p-5 border shadow-xl rounded-3xl bg-n-solid-1 border-n-weak"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.CLEAR.TITLE') }}
        </h3>
        <p class="mb-0 mt-1.5 text-xs leading-relaxed text-n-slate-11">
          {{ t('INTERNAL_CHAT.CLEAR.BODY') }}
        </p>
        <div class="flex justify-end gap-2 mt-4">
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="showClearConfirm = false"
          >
            {{ t('INTERNAL_CHAT.CANCEL') }}
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-semibold text-white rounded-lg bg-n-ruby-9 hover:bg-n-ruby-10"
            @click="confirmClear"
          >
            {{ t('INTERNAL_CHAT.CLEAR.CONFIRM') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
