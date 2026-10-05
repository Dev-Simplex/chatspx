<script setup>
// Chat interno — tela viva, ligada ao store internalChat (backend real).
// Mostra DMs, grupos e "grupos de time" (auto-criados a partir dos Teams da
// conta). Admin pode alternar "Ver todos" para auditar todos os canais.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { brandAssetUrl } from 'shared/helpers/brandAssetUrl';
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

const store = useStore();
const { t } = useI18n();
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

// Tela vazia (nenhuma conversa aberta): logo da marca + botão "Nova conversa".
const chatSidebarRef = ref(null);
const logoVisible = ref(true);
const brandLogo = computed(
  () =>
    globalConfig.value?.logoThumbnail ||
    globalConfig.value?.logo ||
    brandAssetUrl(
      '/brand-assets/logo_thumbnail.svg',
      globalConfig.value?.gitSha
    )
);
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
const threadItems = computed(() => {
  const out = [];
  const isGroup = Boolean(activeConversation.value?.isGroup);
  let lastDay = null;
  let prev = null;
  rawMessages.value.forEach(m => {
    const key = new Date(m.created_at * 1000).toDateString();
    if (key !== lastDay) {
      out.push({
        type: 'day',
        id: `day-${key}`,
        label: dayLabelFor(m.created_at),
      });
      lastDay = key;
      prev = null;
    }
    const mine = m.user?.id === currentUserId.value;
    const continued =
      Boolean(prev) &&
      prev.user?.id === m.user?.id &&
      m.created_at - prev.created_at < GROUP_WINDOW;
    out.push({
      type: 'message',
      id: m.id ?? m.echo_id,
      echoId: m.echo_id,
      mine,
      senderName: m.user?.name,
      avatarSrc: m.user?.avatar_url,
      // Nome em cima só no 1º balão de uma sequência de outra pessoa, em grupo.
      showSender: isGroup && !mine && !continued,
      inGroup: isGroup,
      continued,
      content: m.content,
      time: messageStamp(m.created_at, 'HH:mm'),
      delivery: mine ? deliveryOf(m) : null,
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
  // O selo de não lidas some na hora; o servidor confirma no fetchMessages.
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
      class="relative w-full h-full md:w-[300px] xl:w-[360px] md:flex-shrink-0 md:border-r md:border-n-weak"
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
      <template v-if="activeConversation">
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
          class="flex items-center gap-2 px-4 py-2 border-b md:px-6 border-n-weak bg-n-background flex-shrink-0"
        >
          <div class="relative flex-1">
            <span
              class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="t('INTERNAL_CHAT.THREAD.SEARCH_PLACEHOLDER')"
              class="reset-base w-full h-9 pl-9 pr-3 text-sm transition-colors border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-brand focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10"
            />
          </div>
          <button
            v-tooltip="t('INTERNAL_CHAT.THREAD.CLOSE_SEARCH')"
            type="button"
            class="inline-flex items-center justify-center rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2"
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
          class="px-4 py-3 text-xs text-center md:px-6 flex-shrink-0 text-n-slate-10 bg-n-alpha-1 border-t border-n-weak"
        >
          {{ t('INTERNAL_CHAT.AUDIT.READONLY_HINT') }}
        </div>

        <!-- Info drawer -->
        <template v-if="showInfo">
          <div
            class="absolute inset-0 z-20 lg:hidden bg-n-alpha-black2"
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
              :can-manage="canManage"
              @manage="showManage = true"
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
      </template>

      <div
        v-else
        class="relative flex flex-col items-center justify-center flex-1 w-full px-8 py-16 text-center"
      >
        <div class="flex flex-col items-center max-w-md">
          <div v-if="logoVisible" class="mb-8">
            <img
              :src="brandLogo"
              alt=""
              class="size-20 drop-shadow-sm"
              @error="logoVisible = false"
            />
          </div>

          <h3 class="text-2xl font-semibold text-n-slate-12">
            {{ t('INTERNAL_CHAT.TITLE') }}
          </h3>

          <p
            class="mt-3 text-sm leading-relaxed text-center text-n-slate-11 max-w-sm"
          >
            {{
              conversationList.length
                ? t('INTERNAL_CHAT.EMPTY_STATE.PICK')
                : t('INTERNAL_CHAT.EMPTY_STATE.FIRST')
            }}
          </p>

          <button
            type="button"
            class="wa-empty-cta flex items-center gap-2 mt-8 px-6 h-10 rounded-full text-white font-medium text-sm transition-colors active:scale-[0.97]"
            @click="openNewConversation"
          >
            <span class="i-lucide-message-square-plus size-4" />
            {{ t('INTERNAL_CHAT.EMPTY_STATE.NEW') }}
          </button>

          <ul class="mt-8 space-y-2 text-xs text-left text-n-slate-11">
            <li class="flex items-center gap-2">
              <span class="i-lucide-at-sign size-4 text-n-slate-10" />
              {{ t('INTERNAL_CHAT.EMPTY_STATE.TIP_MENTION') }}
            </li>
            <li class="flex items-center gap-2">
              <span class="i-lucide-hash size-4 text-n-slate-10" />
              {{ t('INTERNAL_CHAT.EMPTY_STATE.TIP_CONVERSATION') }}
            </li>
            <li class="flex items-center gap-2">
              <span class="i-lucide-share-2 size-4 text-n-slate-10" />
              {{ t('INTERNAL_CHAT.EMPTY_STATE.TIP_SHARE') }}
            </li>
          </ul>
        </div>

        <div
          class="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-1.5"
        >
          <span class="i-lucide-lock size-3 text-n-slate-9" />
          <span class="text-xs text-n-slate-9">
            {{ t('INTERNAL_CHAT.EMPTY_STATE.PRIVATE') }}
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
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.CLEAR.TITLE') }}
        </h3>
        <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
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
