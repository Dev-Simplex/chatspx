<script setup>
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
  watch,
  defineAsyncComponent,
} from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import ManageChannelDialog from '../components/ManageChannelDialog.vue';

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const store = useStore();
const { t } = useI18n();
const router = useRouter();

// Open a customer conversation (shared card / #123 link).
const openConversation = displayId => {
  if (!displayId) return;
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: displayId },
  });
};

const channels = useMapGetter('internalChat/getChannels');
const auditChannels = useMapGetter('internalChat/getAuditChannels');
const agents = useMapGetter('internalChat/getAgents');
const uiFlags = useMapGetter('internalChat/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');
const currentRole = useMapGetter('getCurrentRole');
const teams = useMapGetter('teams/getMyTeams');

// Auditoria (admin): alterna a lista para TODOS os canais da conta (somente
// leitura nos canais em que o admin não participa).
const isAdmin = computed(() => currentRole.value === 'administrator');
const auditMode = ref(false);
const channelList = computed(() =>
  auditMode.value ? auditChannels.value : channels.value
);
const toggleAudit = async () => {
  auditMode.value = !auditMode.value;
  if (auditMode.value) await store.dispatch('internalChat/fetchAuditChannels');
};

const activeChannelId = ref(null);
const draft = ref('');
const threadRef = ref(null);
const fileInput = ref(null);
const composerRef = ref(null);
const showScrollDown = ref(false);

// Composer state
const attachedFiles = ref([]);
const mentionedUserIds = ref([]);
const showEmoji = ref(false);
const showMentionPicker = ref(false);
const replyingTo = ref(null);

// New-channel panel: null | 'menu' | 'dm' | 'group' | 'team'
const newPanel = ref(null);
const groupName = ref('');
const groupMemberIds = ref([]);
const showManage = ref(false);

const onChannelLeft = channelId => {
  if (activeChannelId.value === channelId) activeChannelId.value = null;
};

const activeChannel = computed(
  () =>
    channels.value.find(c => c.id === activeChannelId.value) ||
    auditChannels.value.find(c => c.id === activeChannelId.value)
);
// Em auditoria, o admin pode abrir um canal do qual não é membro → somente leitura.
const isMemberOfActiveChannel = computed(() => {
  const channel = activeChannel.value;
  if (!channel) return true;
  return (channel.members || []).some(m => m.id === currentUserId.value);
});
const messages = computed(() =>
  store.getters['internalChat/getMessages'](activeChannelId.value)
);
const channelMembers = computed(() =>
  (activeChannel.value?.members || []).filter(m => m.id !== currentUserId.value)
);

const counterpart = channel =>
  (channel?.members || []).find(m => m.id !== currentUserId.value);

// Avatar (src/name) for a channel row / header.
const channelAvatar = channel => {
  if (channel?.channel_type === 'direct') {
    const other = counterpart(channel);
    return { src: other?.avatar_url, name: other?.name || channel.title };
  }
  return { src: null, name: channel?.title || '#' };
};

const channelSubtitle = channel => {
  if (!channel) return '';
  if (channel.channel_type === 'direct') return t('INTERNAL_CHAT.DIRECT');
  return t('INTERNAL_CHAT.MEMBERS_COUNT', {
    count: (channel.members || []).length,
  });
};

// Presence (Fase 4): availability_status from the agents store (online/busy/offline).
const presenceOf = userId =>
  store.getters['agents/getAgentById'](userId)?.availability_status || null;
const channelStatus = channel => {
  if (channel?.channel_type !== 'direct') return null;
  return presenceOf(counterpart(channel)?.id);
};

// --- date / grouping helpers ------------------------------------------------
const timeLabel = ts => messageStamp(ts, 'HH:mm');

const dayLabel = ts => {
  const d = new Date(ts * 1000);
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString())
    return t('INTERNAL_CHAT.TODAY');
  if (d.toDateString() === yesterday.toDateString())
    return t('INTERNAL_CHAT.YESTERDAY');
  return d.toLocaleDateString();
};

// Flatten messages into day-dividers + messages, grouping consecutive messages
// from the same author within 5 minutes (header shown only on the first).
const groupedItems = computed(() => {
  const out = [];
  let lastDay = null;
  let lastUser = null;
  let lastTs = 0;
  messages.value.forEach(m => {
    const day = new Date(m.created_at * 1000).toDateString();
    if (day !== lastDay) {
      out.push({
        type: 'day',
        id: `day-${day}`,
        label: dayLabel(m.created_at),
      });
      lastDay = day;
      lastUser = null;
    }
    const grouped = m.user?.id === lastUser && m.created_at - lastTs < 300;
    out.push({ type: 'msg', id: m.id, msg: m, showHeader: !grouped });
    lastUser = m.user?.id;
    lastTs = m.created_at;
  });
  return out;
});

// --- attachments / text -----------------------------------------------------
const IMAGE_RE = /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i;
const isImage = att => IMAGE_RE.test(att?.filename || '');

// URLs and #123 conversation references.
const TOKEN_RE = /(https?:\/\/[^\s]+|#\d+)/g;
const textParts = content => {
  const s = String(content || '');
  const out = [];
  let last = 0;
  s.replace(TOKEN_RE, (match, _g, idx) => {
    if (idx > last) out.push({ t: 'text', v: s.slice(last, idx) });
    if (match[0] === '#') out.push({ t: 'conv', v: match, id: match.slice(1) });
    else out.push({ t: 'link', v: match });
    last = idx + match.length;
    return match;
  });
  if (last < s.length) out.push({ t: 'text', v: s.slice(last) });
  return out;
};

// --- scrolling --------------------------------------------------------------
const scrollToBottom = async () => {
  await nextTick();
  if (threadRef.value) threadRef.value.scrollTop = threadRef.value.scrollHeight;
  showScrollDown.value = false;
};

const distanceFromBottom = () => {
  const el = threadRef.value;
  if (!el) return 0;
  return el.scrollHeight - el.scrollTop - el.clientHeight;
};

// --- pagination (Fase 2C): load older history at the top --------------------
const hasMore = computed(() =>
  store.getters['internalChat/getHasMore'](activeChannelId.value)
);
const loadOlder = async () => {
  const el = threadRef.value;
  if (!el || uiFlags.value.isFetchingMessages || !hasMore.value) return;
  const prevHeight = el.scrollHeight;
  const prevTop = el.scrollTop;
  await store.dispatch(
    'internalChat/fetchOlderMessages',
    activeChannelId.value
  );
  await nextTick();
  // Keep the viewport anchored where the user was after prepending older rows.
  el.scrollTop = prevTop + (el.scrollHeight - prevHeight);
};

const onThreadScroll = () => {
  showScrollDown.value = distanceFromBottom() > 240;
  if (threadRef.value && threadRef.value.scrollTop < 80) loadOlder();
};

// --- composer ---------------------------------------------------------------
const autoResize = () => {
  const el = composerRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 140)}px`;
};

const focusComposer = () => {
  nextTick(() => composerRef.value?.focus());
};

const resetComposer = () => {
  draft.value = '';
  attachedFiles.value = [];
  mentionedUserIds.value = [];
  showEmoji.value = false;
  showMentionPicker.value = false;
  replyingTo.value = null;
  nextTick(autoResize);
};

// --- typing indicator (Fase 2B) — defined before openChannel/send (used there)
let typingThrottle = 0;
let typingStopTimer = null;

const stopTyping = () => {
  clearTimeout(typingStopTimer);
  if (!typingThrottle) return;
  typingThrottle = 0;
  if (activeChannelId.value) {
    store.dispatch('internalChat/sendTyping', {
      channelId: activeChannelId.value,
      typing: false,
    });
  }
};

const signalTyping = () => {
  if (!activeChannelId.value) return;
  const now = Date.now();
  if (now - typingThrottle > 2500) {
    typingThrottle = now;
    store.dispatch('internalChat/sendTyping', {
      channelId: activeChannelId.value,
      typing: true,
    });
  }
  clearTimeout(typingStopTimer);
  typingStopTimer = setTimeout(stopTyping, 3500);
};

const onComposerInput = () => {
  autoResize();
  signalTyping();
};

const openChannel = async channel => {
  stopTyping();
  activeChannelId.value = channel.id;
  resetComposer();
  await store.dispatch('internalChat/fetchMessages', channel.id);
  scrollToBottom();
  focusComposer();
};

const closeNewPanel = () => {
  newPanel.value = null;
  groupName.value = '';
  groupMemberIds.value = [];
};

const startDm = async agent => {
  const channel = await store.dispatch('internalChat/createDm', agent.id);
  closeNewPanel();
  if (channel) openChannel(channel);
};

const createGroup = async () => {
  if (!groupMemberIds.value.length) return;
  const channel = await store.dispatch('internalChat/createGroup', {
    name: groupName.value,
    memberIds: groupMemberIds.value,
  });
  closeNewPanel();
  if (channel) openChannel(channel);
};

const createTeamChannel = async team => {
  const channel = await store.dispatch(
    'internalChat/createTeamChannel',
    team.id
  );
  closeNewPanel();
  if (channel) openChannel(channel);
};

const toggleGroupMember = id => {
  const idx = groupMemberIds.value.indexOf(id);
  if (idx === -1) groupMemberIds.value.push(id);
  else groupMemberIds.value.splice(idx, 1);
};

const onEmojiSelect = emoji => {
  draft.value += emoji;
  showEmoji.value = false;
  focusComposer();
  nextTick(autoResize);
};

const onPickFile = () => fileInput.value?.click();
const onFilesSelected = event => {
  attachedFiles.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeFile = index => attachedFiles.value.splice(index, 1);

const mentionMember = member => {
  draft.value = `${draft.value}@${member.name} `.replace(/\s{2,}/g, ' ');
  if (!mentionedUserIds.value.includes(member.id)) {
    mentionedUserIds.value.push(member.id);
  }
  showMentionPicker.value = false;
  focusComposer();
};

const send = async () => {
  const content = draft.value.trim();
  if ((!content && !attachedFiles.value.length) || !activeChannelId.value)
    return;
  const payload = {
    channelId: activeChannelId.value,
    content,
    attachments: attachedFiles.value,
    mentionedUserIds: mentionedUserIds.value,
    replyToId: replyingTo.value?.id || null,
  };
  stopTyping();
  resetComposer();
  await store.dispatch('internalChat/sendMessage', payload);
  scrollToBottom();
};

const isMine = message => message.user?.id === currentUserId.value;
const mentionsMe = message =>
  (message.mentioned_user_ids || []).map(Number).includes(currentUserId.value);

// --- message actions (Fase 2A): edit / delete / reactions -------------------
const QUICK_EMOJIS = ['👍', '❤️', '😂', '🎉', '✅', '🙏'];
const editingId = ref(null);
const editDraft = ref('');
const reactionPickerId = ref(null);
const confirmDeleteId = ref(null);

const startEdit = msg => {
  reactionPickerId.value = null;
  confirmDeleteId.value = null;
  editingId.value = msg.id;
  editDraft.value = msg.content || '';
};
const cancelEdit = () => {
  editingId.value = null;
  editDraft.value = '';
};
const saveEdit = async msg => {
  const content = editDraft.value.trim();
  if (!content) return;
  cancelEdit();
  await store.dispatch('internalChat/editMessage', {
    channelId: activeChannelId.value,
    messageId: msg.id,
    content,
  });
};

const askDelete = msg => {
  reactionPickerId.value = null;
  confirmDeleteId.value = confirmDeleteId.value === msg.id ? null : msg.id;
};
const doDelete = async msg => {
  confirmDeleteId.value = null;
  await store.dispatch('internalChat/deleteMessage', {
    channelId: activeChannelId.value,
    messageId: msg.id,
  });
};

const toggleReactionPicker = msg => {
  confirmDeleteId.value = null;
  reactionPickerId.value = reactionPickerId.value === msg.id ? null : msg.id;
};
const toggleReaction = async (msg, emoji) => {
  reactionPickerId.value = null;
  await store.dispatch('internalChat/reactToMessage', {
    channelId: activeChannelId.value,
    messageId: msg.id,
    emoji,
  });
};
const reactionEntries = msg => Object.entries(msg.reactions || {});
const iReacted = (msg, emoji) =>
  (msg.reactions?.[emoji] || []).map(Number).includes(currentUserId.value);

// --- reply / quote (Fase 2C) ------------------------------------------------
const startReply = msg => {
  reactionPickerId.value = null;
  confirmDeleteId.value = null;
  replyingTo.value = msg;
  focusComposer();
};
const cancelReply = () => {
  replyingTo.value = null;
};
const replyText = msg => {
  if (msg?.deleted) return t('INTERNAL_CHAT.DELETED');
  return msg?.content || '';
};
const scrollToMessage = id => {
  const el = threadRef.value?.querySelector(`[data-msg-id="${id}"]`);
  if (!el) return;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.classList.add('ring-2', 'ring-n-brand/60', 'rounded-2xl');
  setTimeout(
    () => el.classList.remove('ring-2', 'ring-n-brand/60', 'rounded-2xl'),
    1400
  );
};

// --- typing label / read receipts (helpers defined above) -------------------
const typingNames = computed(() =>
  store.getters['internalChat/getTypingNames'](activeChannelId.value)
);
const typingLabel = computed(() => {
  const names = typingNames.value;
  if (!names.length) return '';
  if (names.length === 1)
    return t('INTERNAL_CHAT.TYPING_ONE', { name: names[0] });
  return t('INTERNAL_CHAT.TYPING_MANY', { count: names.length });
});

// --- read receipts (Fase 2B) ------------------------------------------------
const activeMembers = computed(() => activeChannel.value?.members || []);
const myLastMessageId = computed(() => {
  for (let i = messages.value.length - 1; i >= 0; i -= 1) {
    const m = messages.value[i];
    if (isMine(m) && !m.deleted) return m.id;
  }
  return null;
});
const seenByCount = computed(() => {
  const id = myLastMessageId.value;
  if (!id) return 0;
  const msg = messages.value.find(m => m.id === id);
  if (!msg) return 0;
  return activeMembers.value.filter(
    m => m.id !== currentUserId.value && (m.last_read_at || 0) >= msg.created_at
  ).length;
});
const seenLabel = computed(() => {
  if (!seenByCount.value) return '';
  if (activeChannel.value?.channel_type === 'direct')
    return t('INTERNAL_CHAT.SEEN');
  return t('INTERNAL_CHAT.SEEN_BY', { count: seenByCount.value });
});

// Auto-scroll on new messages only when the reader is already near the bottom.
watch(
  () => messages.value.length,
  (n, o) => {
    if (n > o) {
      if (distanceFromBottom() < 240) scrollToBottom();
      else showScrollDown.value = true;
    }
  }
);

onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
  store.dispatch('teams/get');
  store.dispatch('agents/get'); // presence (availability_status)
});

// Ao sair da tela do chat, nenhum canal está "aberto" → todas as mensagens
// voltam a notificar (som/toast) mesmo trabalhando em outra parte do sistema.
onBeforeUnmount(() => {
  store.dispatch('internalChat/clearActiveChannel');
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background">
    <!-- ============ Channel list ============ -->
    <aside
      class="flex flex-col w-80 h-full border-r border-n-weak flex-shrink-0 bg-n-solid-1"
    >
      <header
        class="flex items-center justify-between px-4 h-14 border-b border-n-weak flex-shrink-0"
      >
        <h1 class="text-base font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.TITLE') }}
        </h1>
        <div class="flex items-center gap-1">
          <button
            v-if="isAdmin"
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
            :class="
              auditMode
                ? 'bg-n-brand/15 text-n-brand'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :title="
              auditMode
                ? t('INTERNAL_CHAT.AUDIT.ON')
                : t('INTERNAL_CHAT.AUDIT.OFF')
            "
            @click="toggleAudit"
          >
            <span class="i-lucide-shield-check text-lg" />
          </button>
          <button
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
            :title="t('INTERNAL_CHAT.NEW_DM')"
            @click="newPanel = newPanel ? null : 'menu'"
          >
            <span class="i-lucide-plus text-lg" />
          </button>
        </div>
      </header>

      <!-- New-channel panel -->
      <div
        v-if="newPanel"
        class="border-b border-n-weak max-h-80 overflow-y-auto flex-shrink-0"
      >
        <template v-if="newPanel === 'menu'">
          <button
            class="flex items-center gap-2.5 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'dm'"
          >
            <span class="i-lucide-user-round text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_DM') }}
          </button>
          <button
            class="flex items-center gap-2.5 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'group'"
          >
            <span class="i-lucide-users text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_GROUP') }}
          </button>
          <button
            class="flex items-center gap-2.5 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'team'"
          >
            <span class="i-lucide-users-round text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_TEAM_CHANNEL') }}
          </button>
        </template>

        <template v-else-if="newPanel === 'dm'">
          <p class="px-4 py-2 text-xs font-medium uppercase text-n-slate-10">
            {{ t('INTERNAL_CHAT.START_WITH') }}
          </p>
          <button
            v-for="agent in agents"
            :key="agent.id"
            class="flex items-center gap-2.5 w-full px-4 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="startDm(agent)"
          >
            <Avatar
              :src="agent.avatar_url"
              :name="agent.name"
              :size="24"
              :status="presenceOf(agent.id)"
              rounded-full
            />
            {{ agent.name }}
          </button>
          <p v-if="!agents.length" class="px-4 py-3 text-sm text-n-slate-10">
            {{ t('INTERNAL_CHAT.NO_AGENTS') }}
          </p>
        </template>

        <template v-else-if="newPanel === 'group'">
          <div class="px-4 py-3 space-y-3">
            <input
              v-model="groupName"
              type="text"
              class="w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg focus:outline-none focus:border-n-brand"
              :placeholder="t('INTERNAL_CHAT.GROUP_NAME_PLACEHOLDER')"
            />
            <p class="text-xs font-medium uppercase text-n-slate-10">
              {{ t('INTERNAL_CHAT.MEMBERS') }}
            </p>
            <label
              v-for="agent in agents"
              :key="agent.id"
              class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
            >
              <input
                type="checkbox"
                :checked="groupMemberIds.includes(agent.id)"
                @change="toggleGroupMember(agent.id)"
              />
              <Avatar
                :src="agent.avatar_url"
                :name="agent.name"
                :size="20"
                rounded-full
              />
              {{ agent.name }}
            </label>
            <div class="flex gap-2 pt-1">
              <button
                class="flex-1 h-8 text-sm font-medium text-white bg-n-brand rounded-lg disabled:opacity-50"
                :disabled="!groupMemberIds.length"
                @click="createGroup"
              >
                {{ t('INTERNAL_CHAT.CREATE') }}
              </button>
              <button
                class="px-3 h-8 text-sm text-n-slate-11"
                @click="closeNewPanel"
              >
                {{ t('INTERNAL_CHAT.CANCEL') }}
              </button>
            </div>
          </div>
        </template>

        <template v-else-if="newPanel === 'team'">
          <p class="px-4 py-2 text-xs font-medium uppercase text-n-slate-10">
            {{ t('INTERNAL_CHAT.SELECT_TEAM') }}
          </p>
          <button
            v-for="team in teams"
            :key="team.id"
            class="flex items-center gap-2.5 w-full px-4 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="createTeamChannel(team)"
          >
            <span class="i-lucide-users-round text-n-slate-10" />
            {{ team.name }}
          </button>
          <p v-if="!teams.length" class="px-4 py-3 text-sm text-n-slate-10">
            {{ t('INTERNAL_CHAT.NO_TEAMS') }}
          </p>
        </template>
      </div>

      <!-- Channels -->
      <div class="flex-1 overflow-y-auto py-1">
        <button
          v-for="channel in channelList"
          :key="channel.id"
          class="flex items-center gap-3 w-full px-3 py-2.5 text-left rounded-lg mx-1 transition-colors"
          :class="
            channel.id === activeChannelId
              ? 'bg-n-alpha-2'
              : 'hover:bg-n-alpha-1'
          "
          @click="openChannel(channel)"
        >
          <Avatar
            :src="channelAvatar(channel).src"
            :name="channelAvatar(channel).name"
            :size="38"
            :status="channelStatus(channel)"
            rounded-full
          />
          <span class="flex-1 min-w-0">
            <span class="flex items-center justify-between gap-2">
              <span
                class="text-sm font-medium text-n-slate-12 truncate"
                :class="{ 'font-semibold': channel.unread_count }"
              >
                {{ channel.title }}
              </span>
              <span
                v-if="channel.last_message"
                class="text-[11px] text-n-slate-10 flex-shrink-0"
              >
                {{ timeLabel(channel.last_message.created_at) }}
              </span>
            </span>
            <span class="flex items-center justify-between gap-2 mt-0.5">
              <span
                class="block text-xs truncate"
                :class="
                  channel.unread_count
                    ? 'text-n-slate-12 font-medium'
                    : 'text-n-slate-10'
                "
              >
                {{
                  channel.last_message
                    ? channel.last_message.content
                    : channelSubtitle(channel)
                }}
              </span>
              <span
                v-if="channel.unread_count"
                class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1.5 text-[10px] font-semibold text-white bg-n-brand rounded-full flex-shrink-0"
              >
                {{ channel.unread_count }}
              </span>
            </span>
          </span>
        </button>

        <div
          v-if="!channelList.length && !uiFlags.isFetchingChannels"
          class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
        >
          <span class="i-lucide-messages-square text-3xl mb-2 opacity-70" />
          <p class="text-sm">{{ t('INTERNAL_CHAT.EMPTY') }}</p>
        </div>
      </div>
    </aside>

    <!-- ============ Thread ============ -->
    <section class="flex flex-col flex-1 h-full min-w-0">
      <template v-if="activeChannel">
        <header
          class="flex items-center gap-3 px-5 h-14 border-b border-n-weak flex-shrink-0"
        >
          <Avatar
            :src="channelAvatar(activeChannel).src"
            :name="channelAvatar(activeChannel).name"
            :size="34"
            :status="channelStatus(activeChannel)"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <h2
              class="text-sm font-semibold text-n-slate-12 truncate leading-tight"
            >
              {{ activeChannel.title }}
            </h2>
            <p class="text-xs text-n-slate-10 truncate leading-tight">
              {{ channelSubtitle(activeChannel) }}
            </p>
          </div>
          <button
            v-if="activeChannel.channel_type === 'group_chat'"
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
            :title="t('INTERNAL_CHAT.MANAGE.TITLE')"
            @click="showManage = true"
          >
            <span class="i-lucide-settings-2 text-lg" />
          </button>
        </header>

        <!-- Messages -->
        <div class="relative flex-1 min-h-0">
          <div
            ref="threadRef"
            class="absolute inset-0 overflow-y-auto px-5 py-4 space-y-1"
            @scroll="onThreadScroll"
          >
            <div
              v-if="uiFlags.isFetchingMessages && !messages.length"
              class="flex justify-center py-8 text-n-slate-10 text-sm"
            >
              {{ t('INTERNAL_CHAT.LOADING') }}
            </div>

            <template v-for="item in groupedItems" :key="item.id">
              <!-- Day divider -->
              <div
                v-if="item.type === 'day'"
                class="flex items-center justify-center my-4"
              >
                <span
                  class="px-3 py-1 text-[11px] font-medium text-n-slate-11 bg-n-alpha-2 rounded-full"
                >
                  {{ item.label }}
                </span>
              </div>

              <!-- Message row -->
              <div
                v-else
                :data-msg-id="item.msg.id"
                class="flex items-end gap-2"
                :class="[
                  isMine(item.msg) ? 'flex-row-reverse' : 'flex-row',
                  item.showHeader ? 'mt-2' : 'mt-0.5',
                ]"
              >
                <!-- avatar gutter (left messages only) -->
                <div class="w-8 flex-shrink-0">
                  <Avatar
                    v-if="!isMine(item.msg) && item.showHeader"
                    :src="item.msg.user?.avatar_url"
                    :name="item.msg.user?.name"
                    :size="28"
                    rounded-full
                  />
                </div>

                <div
                  class="group relative max-w-[68%] flex flex-col"
                  :class="isMine(item.msg) ? 'items-end' : 'items-start'"
                >
                  <span
                    v-if="item.showHeader && !isMine(item.msg)"
                    class="text-xs font-medium text-n-slate-11 mb-0.5 px-1"
                  >
                    {{ item.msg.user?.name }}
                  </span>

                  <!-- deleted -->
                  <div
                    v-if="item.msg.deleted"
                    class="flex items-center gap-1.5 px-3 py-2 rounded-2xl text-sm italic text-n-slate-10 bg-n-alpha-1"
                  >
                    <span class="i-lucide-ban text-sm" />
                    {{ t('INTERNAL_CHAT.DELETED') }}
                  </div>

                  <!-- editing -->
                  <div
                    v-else-if="editingId === item.msg.id"
                    class="flex flex-col gap-1.5 w-[260px]"
                  >
                    <textarea
                      v-model="editDraft"
                      rows="2"
                      class="w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-xl text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
                      @keydown.enter.exact.prevent="saveEdit(item.msg)"
                      @keydown.esc="cancelEdit"
                    />
                    <div class="flex gap-3 text-xs px-1">
                      <button
                        class="font-medium text-n-brand"
                        @click="saveEdit(item.msg)"
                      >
                        {{ t('INTERNAL_CHAT.SAVE_EDIT') }}
                      </button>
                      <button class="text-n-slate-10" @click="cancelEdit">
                        {{ t('INTERNAL_CHAT.CANCEL') }}
                      </button>
                    </div>
                  </div>

                  <!-- normal -->
                  <div
                    v-else
                    class="relative px-3 py-2 rounded-2xl text-sm break-words"
                    :class="[
                      isMine(item.msg)
                        ? 'bg-n-brand text-white rounded-br-sm'
                        : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm',
                      mentionsMe(item.msg) ? 'ring-2 ring-n-brand/60' : '',
                    ]"
                  >
                    <!-- hover toolbar -->
                    <div
                      class="absolute -top-3 z-10 hidden group-hover:flex items-center gap-0.5 bg-n-solid-1 border border-n-weak rounded-full shadow px-1 py-0.5"
                      :class="isMine(item.msg) ? 'right-1' : 'left-1'"
                    >
                      <button
                        class="inline-flex items-center justify-center w-6 h-6 rounded-full text-n-slate-11 hover:bg-n-alpha-2"
                        :title="t('INTERNAL_CHAT.REPLY')"
                        @click="startReply(item.msg)"
                      >
                        <span class="i-lucide-reply text-sm" />
                      </button>
                      <button
                        class="inline-flex items-center justify-center w-6 h-6 rounded-full text-n-slate-11 hover:bg-n-alpha-2"
                        :title="t('INTERNAL_CHAT.REACT')"
                        @click="toggleReactionPicker(item.msg)"
                      >
                        <span class="i-lucide-smile-plus text-sm" />
                      </button>
                      <button
                        v-if="isMine(item.msg)"
                        class="inline-flex items-center justify-center w-6 h-6 rounded-full text-n-slate-11 hover:bg-n-alpha-2"
                        :title="t('INTERNAL_CHAT.EDIT')"
                        @click="startEdit(item.msg)"
                      >
                        <span class="i-lucide-pencil text-sm" />
                      </button>
                      <button
                        v-if="isMine(item.msg)"
                        class="inline-flex items-center justify-center w-6 h-6 rounded-full text-n-slate-11 hover:bg-n-alpha-2"
                        :title="t('INTERNAL_CHAT.DELETE')"
                        @click="askDelete(item.msg)"
                      >
                        <span class="i-lucide-trash-2 text-sm" />
                      </button>
                    </div>

                    <!-- reaction picker -->
                    <div
                      v-if="reactionPickerId === item.msg.id"
                      class="absolute -top-9 z-20 flex gap-1 bg-n-solid-1 border border-n-weak rounded-full shadow px-2 py-1"
                      :class="isMine(item.msg) ? 'right-1' : 'left-1'"
                    >
                      <button
                        v-for="e in QUICK_EMOJIS"
                        :key="e"
                        class="text-base leading-none hover:scale-125 transition-transform"
                        @click="toggleReaction(item.msg, e)"
                      >
                        {{ e }}
                      </button>
                    </div>

                    <!-- delete confirm -->
                    <div
                      v-if="confirmDeleteId === item.msg.id"
                      class="absolute -top-9 z-20 flex items-center gap-2 bg-n-solid-1 border border-n-weak rounded-lg shadow px-2 py-1 text-xs"
                      :class="isMine(item.msg) ? 'right-1' : 'left-1'"
                    >
                      <span class="text-n-slate-11 whitespace-nowrap">{{
                        t('INTERNAL_CHAT.DELETE_Q')
                      }}</span>
                      <button
                        class="font-medium text-n-ruby-11"
                        @click="doDelete(item.msg)"
                      >
                        {{ t('INTERNAL_CHAT.DELETE') }}
                      </button>
                      <button
                        class="text-n-slate-10"
                        @click="confirmDeleteId = null"
                      >
                        {{ t('INTERNAL_CHAT.CANCEL') }}
                      </button>
                    </div>

                    <!-- quoted message -->
                    <button
                      v-if="item.msg.reply_to"
                      class="block w-full text-left mb-1 pl-2 border-l-2 rounded-sm opacity-90"
                      :class="
                        isMine(item.msg) ? 'border-white/60' : 'border-n-brand'
                      "
                      @click="scrollToMessage(item.msg.reply_to.id)"
                    >
                      <span class="block text-[11px] font-semibold">{{
                        item.msg.reply_to.user_name
                      }}</span>
                      <span class="block text-[11px] opacity-75 truncate">{{
                        replyText(item.msg.reply_to)
                      }}</span>
                    </button>

                    <p
                      v-if="item.msg.content"
                      class="whitespace-pre-wrap leading-relaxed"
                    >
                      <template
                        v-for="(part, i) in textParts(item.msg.content)"
                        :key="i"
                      >
                        <a
                          v-if="part.t === 'link'"
                          :href="part.v"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="underline break-all"
                          >{{ part.v }}</a
                        >
                        <button
                          v-else-if="part.t === 'conv'"
                          class="font-semibold underline"
                          @click.stop="openConversation(part.id)"
                        >
                          {{ part.v }}
                        </button>
                        <template v-else>{{ part.v }}</template>
                      </template>
                      <span
                        v-if="item.msg.edited"
                        class="text-[10px] opacity-60 ml-1 align-baseline"
                        >{{ t('INTERNAL_CHAT.EDITED') }}</span
                      >
                    </p>

                    <!-- attachments -->
                    <div
                      v-if="(item.msg.attachments || []).length"
                      class="flex flex-col gap-1.5"
                      :class="{ 'mt-1.5': item.msg.content }"
                    >
                      <template
                        v-for="att in item.msg.attachments"
                        :key="att.id"
                      >
                        <a
                          v-if="isImage(att)"
                          :href="att.url"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="block"
                        >
                          <img
                            :src="att.url"
                            :alt="att.filename"
                            class="max-w-[220px] max-h-[220px] rounded-lg object-cover"
                          />
                        </a>
                        <a
                          v-else
                          :href="att.url"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="flex items-center gap-1.5 text-xs underline opacity-90"
                        >
                          <span class="i-lucide-paperclip" />
                          {{ att.filename }}
                        </a>
                      </template>
                    </div>

                    <!-- shared conversation card -->
                    <button
                      v-if="item.msg.shared_conversation"
                      class="flex flex-col items-start gap-0.5 w-full mt-1.5 px-2.5 py-2 rounded-lg text-left bg-n-solid-1 border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
                      @click.stop="
                        openConversation(
                          item.msg.shared_conversation.display_id
                        )
                      "
                    >
                      <span
                        class="flex items-center gap-1.5 text-xs font-semibold"
                      >
                        <span
                          class="i-lucide-message-square-text text-n-slate-10"
                        />
                        #{{ item.msg.shared_conversation.display_id }}
                        <span v-if="item.msg.shared_conversation.contact_name">
                          · {{ item.msg.shared_conversation.contact_name }}
                        </span>
                      </span>
                      <span class="text-[11px] text-n-slate-10">
                        {{ item.msg.shared_conversation.inbox_name }}
                        <span v-if="item.msg.shared_conversation.status">
                          · {{ item.msg.shared_conversation.status }}
                        </span>
                      </span>
                    </button>
                  </div>

                  <!-- reaction chips -->
                  <div
                    v-if="!item.msg.deleted && reactionEntries(item.msg).length"
                    class="flex flex-wrap gap-1 mt-1"
                    :class="isMine(item.msg) ? 'justify-end' : 'justify-start'"
                  >
                    <button
                      v-for="[emoji, users] in reactionEntries(item.msg)"
                      :key="emoji"
                      class="inline-flex items-center gap-1 px-1.5 h-5 text-xs rounded-full border transition-colors"
                      :class="
                        iReacted(item.msg, emoji)
                          ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                          : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                      "
                      @click="toggleReaction(item.msg, emoji)"
                    >
                      <span>{{ emoji }}</span>
                      <span>{{ users.length }}</span>
                    </button>
                  </div>

                  <span
                    class="text-[10px] text-n-slate-9 mt-0.5 px-1 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    {{ timeLabel(item.msg.created_at) }}
                  </span>
                </div>
              </div>
            </template>

            <!-- read receipt under my last message -->
            <div v-if="seenLabel" class="flex justify-end px-1 pt-0.5">
              <span class="text-[10px] text-n-slate-9">{{ seenLabel }}</span>
            </div>
          </div>

          <!-- scroll-to-bottom -->
          <button
            v-if="showScrollDown"
            class="absolute bottom-4 right-4 inline-flex items-center justify-center w-9 h-9 rounded-full bg-n-solid-1 border border-n-weak shadow-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="scrollToBottom"
          >
            <span class="i-lucide-chevron-down text-lg" />
          </button>
        </div>

        <!-- Auditoria (admin não-membro): somente leitura, sem composer -->
        <div
          v-if="!isMemberOfActiveChannel"
          class="px-4 py-3 border-t border-n-weak flex items-center justify-center gap-2 text-xs text-n-slate-10 flex-shrink-0"
        >
          <span class="i-lucide-shield-check" />
          {{ t('INTERNAL_CHAT.AUDIT.READONLY') }}
        </div>

        <!-- Composer -->
        <footer
          v-else
          class="px-4 py-3 border-t border-n-weak relative flex-shrink-0"
        >
          <div
            v-if="typingLabel"
            class="absolute -top-5 left-5 text-xs italic text-n-slate-10"
          >
            {{ typingLabel }}
          </div>

          <!-- replying-to bar -->
          <div
            v-if="replyingTo"
            class="flex items-center gap-2 mb-2 px-2 py-1.5 bg-n-alpha-1 border-l-2 border-n-brand rounded-r-lg"
          >
            <span class="i-lucide-reply text-n-slate-10 flex-shrink-0" />
            <span class="flex-1 min-w-0">
              <span class="block text-xs font-medium text-n-slate-12">{{
                replyingTo.user?.name
              }}</span>
              <span class="block text-xs text-n-slate-10 truncate">{{
                replyText(replyingTo)
              }}</span>
            </span>
            <button
              class="i-lucide-x text-n-slate-10 hover:text-n-slate-12 flex-shrink-0"
              @click="cancelReply"
            />
          </div>

          <div v-if="attachedFiles.length" class="flex flex-wrap gap-2 mb-2">
            <span
              v-for="(file, index) in attachedFiles"
              :key="index"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs bg-n-alpha-2 rounded-md"
            >
              <span class="i-lucide-paperclip" />
              {{ file.name }}
              <button class="i-lucide-x" @click="removeFile(index)" />
            </span>
          </div>

          <div
            v-if="showMentionPicker && channelMembers.length"
            class="absolute bottom-16 left-4 w-56 max-h-48 overflow-y-auto bg-n-solid-1 border border-n-weak rounded-lg shadow-lg z-10"
          >
            <button
              v-for="member in channelMembers"
              :key="member.id"
              class="flex items-center gap-2 w-full px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
              @click="mentionMember(member)"
            >
              <Avatar
                :src="member.avatar_url"
                :name="member.name"
                :size="22"
                rounded-full
              />
              {{ member.name }}
            </button>
          </div>

          <EmojiInput
            v-if="showEmoji"
            class="absolute bottom-16 right-4 z-10"
            :on-click="onEmojiSelect"
          />

          <div
            class="flex items-end gap-1 bg-n-alpha-1 border border-n-weak rounded-2xl px-2 py-1.5 focus-within:border-n-brand transition-colors"
          >
            <button
              class="inline-flex items-center justify-center h-8 w-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
              :title="t('INTERNAL_CHAT.ATTACH')"
              @click="onPickFile"
            >
              <span class="i-lucide-paperclip text-lg" />
            </button>
            <button
              class="inline-flex items-center justify-center h-8 w-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
              @click="showEmoji = !showEmoji"
            >
              <span class="i-lucide-smile text-lg" />
            </button>
            <button
              v-if="channelMembers.length"
              class="inline-flex items-center justify-center h-8 w-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
              @click="showMentionPicker = !showMentionPicker"
            >
              <span class="i-lucide-at-sign text-lg" />
            </button>
            <input
              ref="fileInput"
              type="file"
              multiple
              class="hidden"
              @change="onFilesSelected"
            />
            <textarea
              ref="composerRef"
              v-model="draft"
              rows="1"
              class="flex-1 resize-none bg-transparent px-2 py-1.5 text-sm text-n-slate-12 focus:outline-none max-h-[140px] leading-relaxed"
              :placeholder="t('INTERNAL_CHAT.PLACEHOLDER')"
              @input="onComposerInput"
              @keydown.enter.exact.prevent="send"
            />
            <button
              class="inline-flex items-center justify-center h-8 w-8 rounded-lg text-white bg-n-brand hover:opacity-90 disabled:opacity-40 flex-shrink-0 self-end"
              :disabled="
                (!draft.trim() && !attachedFiles.length) || uiFlags.isSending
              "
              @click="send"
            >
              <span class="i-lucide-send-horizontal text-base" />
            </button>
          </div>
        </footer>
      </template>

      <!-- empty (no channel selected) -->
      <div
        v-else
        class="flex flex-col items-center justify-center flex-1 text-n-slate-10"
      >
        <span class="i-lucide-messages-square text-5xl mb-3 opacity-60" />
        <p class="text-sm font-medium text-n-slate-11">
          {{ t('INTERNAL_CHAT.SELECT_PROMPT') }}
        </p>
      </div>
    </section>

    <ManageChannelDialog
      v-if="showManage"
      :show="showManage"
      :channel="activeChannel"
      @close="showManage = false"
      @left="onChannelLeft"
    />
  </div>
</template>
