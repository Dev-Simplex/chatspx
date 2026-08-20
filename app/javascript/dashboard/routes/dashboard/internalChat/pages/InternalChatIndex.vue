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
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import getUuid from 'widget/helpers/uuid';
import {
  checkFileSizeLimit,
  HARD_MAXIMUM_FILE_UPLOAD_SIZE,
} from 'shared/helpers/FileHelper';
import ManageChannelDialog from '../components/ManageChannelDialog.vue';

const EmojiPicker = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiPicker.vue')
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

// ── Notification preferences (desktop + sound) ────────────────────────────
// Persisted in the user's UI settings and honored by Sidebar.vue when a new
// internal message arrives. Defaults: both ON (preserves prior behavior).
const { uiSettings, updateUISettings } = useUISettings();
const showNotifSettings = ref(false);
const desktopPermissionBlocked = ref(false);
const desktopNotifications = computed(
  () => uiSettings.value?.internal_chat_desktop_notifications !== false
);
const soundNotifications = computed(
  () => uiSettings.value?.internal_chat_sound_notifications !== false
);
const toggleSoundNotifications = () => {
  updateUISettings({
    internal_chat_sound_notifications: !soundNotifications.value,
  });
};
const toggleDesktopNotifications = () => {
  const next = !desktopNotifications.value;
  // Turning desktop notifications ON needs browser permission.
  if (next && 'Notification' in window) {
    if (Notification.permission === 'denied') {
      desktopPermissionBlocked.value = true;
      updateUISettings({ internal_chat_desktop_notifications: true });
      return;
    }
    if (Notification.permission === 'default') {
      Notification.requestPermission()
        .then(p => {
          desktopPermissionBlocked.value = p === 'denied';
          updateUISettings({
            internal_chat_desktop_notifications: p !== 'denied',
          });
        })
        .catch(() => {});
      return;
    }
  }
  desktopPermissionBlocked.value = false;
  updateUISettings({ internal_chat_desktop_notifications: next });
};

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

// Fase 0.4: client-side search over the channel list (matches the title).
const channelSearch = ref('');
const filteredChannelList = computed(() => {
  const q = channelSearch.value.trim().toLowerCase();
  if (!q) return channelList.value;
  return channelList.value.filter(c =>
    (c.title || '').toLowerCase().includes(q)
  );
});

// Fase 0.3: retry a failed channel-list load (honors audit mode).
const retryFetchChannels = () => {
  if (auditMode.value) store.dispatch('internalChat/fetchAuditChannels');
  else store.dispatch('internalChat/fetchChannels');
};

// Fase 3: aside views — 'channels' (default) | 'mentions' | 'search'.
const asideView = ref('channels');
const messageSearch = ref('');
const mentions = useMapGetter('internalChat/getMentions');
const searchResults = useMapGetter('internalChat/getSearchResults');

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
// Fase 1.3: the "@" prefix currently being typed, used to filter the picker.
const mentionQuery = ref('');
const replyingTo = ref(null);
// Fase 0.7: unsent composer state (text + attachments + reply) kept per channel,
// so switching conversations no longer discards what you were typing.
const draftsByChannel = ref({});

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

// Fase 0.5: last-message preview honoring soft-delete and attachment-only rows.
const channelPreview = channel => {
  const lastMessage = channel?.last_message;
  if (!lastMessage) return channelSubtitle(channel);
  if (lastMessage.deleted) return t('INTERNAL_CHAT.DELETED');
  return lastMessage.content || t('INTERNAL_CHAT.ATTACHMENT');
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

// Fase 1.3: a regex that matches "@<known agent name>" (longest name first so
// multi-word names win), used to highlight mentions in rendered text.
const mentionNamesRe = computed(() => {
  const names = (agents.value || [])
    .map(a => a.name)
    .filter(Boolean)
    .sort((a, b) => b.length - a.length)
    .map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return names.length ? new RegExp(`@(?:${names.join('|')})`, 'g') : null;
});

const textParts = content => {
  const s = String(content || '');
  const base = [];
  let last = 0;
  s.replace(TOKEN_RE, (match, _g, idx) => {
    if (idx > last) base.push({ t: 'text', v: s.slice(last, idx) });
    if (match[0] === '#')
      base.push({ t: 'conv', v: match, id: match.slice(1) });
    else base.push({ t: 'link', v: match });
    last = idx + match.length;
    return match;
  });
  if (last < s.length) base.push({ t: 'text', v: s.slice(last) });

  // Second pass: highlight @mentions inside the plain-text segments.
  const re = mentionNamesRe.value;
  if (!re) return base;
  const out = [];
  base.forEach(part => {
    if (part.t !== 'text') {
      out.push(part);
      return;
    }
    const seg = part.v;
    let l = 0;
    re.lastIndex = 0;
    seg.replace(re, (m, idx) => {
      if (idx > l) out.push({ t: 'text', v: seg.slice(l, idx) });
      out.push({ t: 'mention', v: m });
      l = idx + m.length;
      return m;
    });
    if (l < seg.length) out.push({ t: 'text', v: seg.slice(l) });
  });
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

// autoResize can mis-measure before web fonts finish loading (FOUT), leaving the
// empty textarea stuck a row too tall. Run it now and again once fonts settle.
const resizeComposerSoon = () => {
  nextTick(autoResize);
  if (typeof document !== 'undefined' && document.fonts?.ready) {
    document.fonts.ready.then(() => nextTick(autoResize)).catch(() => {});
  }
};

const resetComposer = () => {
  draft.value = '';
  attachedFiles.value = [];
  mentionedUserIds.value = [];
  showEmoji.value = false;
  showMentionPicker.value = false;
  replyingTo.value = null;
  resizeComposerSoon();
};

// Fase 0.7: persist the current composer under a channel id (or clear it when
// empty), and restore it when the channel is reopened.
const saveDraft = channelId => {
  if (!channelId) return;
  const hasContent =
    Boolean(draft.value.trim()) ||
    attachedFiles.value.length > 0 ||
    Boolean(replyingTo.value);
  const next = { ...draftsByChannel.value };
  if (hasContent) {
    next[channelId] = {
      draft: draft.value,
      attachedFiles: attachedFiles.value,
      mentionedUserIds: mentionedUserIds.value,
      replyingTo: replyingTo.value,
    };
  } else {
    delete next[channelId];
  }
  draftsByChannel.value = next;
};

const restoreDraft = channelId => {
  const saved = draftsByChannel.value[channelId];
  draft.value = saved?.draft || '';
  attachedFiles.value = saved?.attachedFiles || [];
  mentionedUserIds.value = saved?.mentionedUserIds || [];
  replyingTo.value = saved?.replyingTo || null;
  showEmoji.value = false;
  showMentionPicker.value = false;
  resizeComposerSoon();
};

const clearDraft = channelId => {
  if (!channelId || !draftsByChannel.value[channelId]) return;
  const next = { ...draftsByChannel.value };
  delete next[channelId];
  draftsByChannel.value = next;
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

// Fase 1.3: inline @mentions — regexes + the trigger that opens/filters the
// picker while typing (defined before onComposerInput, which calls it).
const MENTION_TOKEN = /@([\p{L}\d._-]*)$/u;
const MENTION_TRIGGER = /(?:^|\s)@([\p{L}\d._-]*)$/u;

const detectMentionTrigger = () => {
  const el = composerRef.value;
  if (!el) return;
  const match = draft.value.slice(0, el.selectionStart).match(MENTION_TRIGGER);
  if (match) {
    mentionQuery.value = match[1];
    showMentionPicker.value = true;
  } else if (showMentionPicker.value) {
    showMentionPicker.value = false;
    mentionQuery.value = '';
  }
};

const onComposerInput = () => {
  autoResize();
  signalTyping();
  detectMentionTrigger();
};

const openChannel = async channel => {
  if (channel.id === activeChannelId.value) return;
  stopTyping();
  saveDraft(activeChannelId.value);
  activeChannelId.value = channel.id;
  restoreDraft(channel.id);
  await store.dispatch('internalChat/fetchMessages', channel.id);
  scrollToBottom();
  focusComposer();
};

// Fase 1.4 (mobile): return from the open thread to the channel list. Keeps the
// draft and stops treating the channel as "active" (so it notifies again).
const backToList = () => {
  saveDraft(activeChannelId.value);
  activeChannelId.value = null;
  store.dispatch('internalChat/clearActiveChannel');
};

// --- Fase 3: mentions inbox + message search (aside views) ------------------
let messageSearchTimer = null;
const openMentions = () => {
  asideView.value = 'mentions';
  store.dispatch('internalChat/fetchMentions');
};
const openMessageSearch = () => {
  asideView.value = 'search';
};
const backToChannels = () => {
  asideView.value = 'channels';
  messageSearch.value = '';
  store.dispatch('internalChat/searchMessages', '');
};
const onMessageSearchInput = () => {
  clearTimeout(messageSearchTimer);
  const q = messageSearch.value;
  messageSearchTimer = setTimeout(() => {
    store.dispatch('internalChat/searchMessages', q);
  }, 300);
};
// Open the channel a result belongs to (best-effort jump to the conversation).
const openResult = result => {
  const target =
    channels.value.find(c => c.id === result.internal_channel_id) ||
    auditChannels.value.find(c => c.id === result.internal_channel_id);
  asideView.value = 'channels';
  if (target) openChannel(target);
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

const onEmojiSelect = ({ value }) => {
  draft.value += value;
  showEmoji.value = false;
  focusComposer();
  nextTick(autoResize);
};

const onPickFile = () => fileInput.value?.click();
const onFilesSelected = event => {
  // Fase 0.6: reject files above the hard upload cap with a clear message,
  // instead of letting the backend fail the whole send.
  Array.from(event.target.files || []).forEach(file => {
    if (checkFileSizeLimit(file, HARD_MAXIMUM_FILE_UPLOAD_SIZE)) {
      attachedFiles.value.push(file);
    } else {
      useAlert(
        t('INTERNAL_CHAT.ATTACHMENT_TOO_LARGE', {
          name: file.name,
          size: HARD_MAXIMUM_FILE_UPLOAD_SIZE,
        })
      );
    }
  });
  event.target.value = '';
};
const removeFile = index => attachedFiles.value.splice(index, 1);

// Picker filtered by the "@" prefix; choosing a member replaces the token and
// records the id (re-validated against the text on send — see validMentionIds).
const filteredMentionMembers = computed(() => {
  const q = mentionQuery.value.toLowerCase();
  const list = channelMembers.value;
  if (!q) return list;
  return list.filter(m => (m.name || '').toLowerCase().includes(q));
});

// Open the picker by inserting an "@" at the caret; typing then filters it.
const openMentionPicker = () => {
  const el = composerRef.value;
  const caret = el ? el.selectionStart : draft.value.length;
  const before = draft.value.slice(0, caret);
  const after = draft.value.slice(caret);
  const needsSpace = before && !before.endsWith(' ');
  draft.value = `${before}${needsSpace ? ' ' : ''}@${after}`;
  mentionQuery.value = '';
  showMentionPicker.value = true;
  nextTick(() => {
    const pos = before.length + (needsSpace ? 1 : 0) + 1;
    if (el) {
      el.focus();
      el.selectionStart = pos;
      el.selectionEnd = pos;
    }
  });
};

const applyMention = member => {
  const el = composerRef.value;
  const text = draft.value;
  const caret = el ? el.selectionStart : text.length;
  const before = text.slice(0, caret);
  const after = text.slice(caret);
  const newBefore = MENTION_TOKEN.test(before)
    ? before.replace(MENTION_TOKEN, `@${member.name} `)
    : `${before}${before && !before.endsWith(' ') ? ' ' : ''}@${member.name} `;
  draft.value = newBefore + after;
  if (!mentionedUserIds.value.includes(member.id)) {
    mentionedUserIds.value.push(member.id);
  }
  showMentionPicker.value = false;
  mentionQuery.value = '';
  nextTick(() => {
    if (el) {
      el.focus();
      el.selectionStart = newBefore.length;
      el.selectionEnd = newBefore.length;
    }
  });
};

// Keep only mentions whose "@Name" still appears in the text (no phantoms).
const validMentionIds = content =>
  mentionedUserIds.value.filter(id => {
    const member = channelMembers.value.find(m => m.id === id);
    return member && content.includes(`@${member.name}`);
  });

const send = async () => {
  const content = draft.value.trim();
  if ((!content && !attachedFiles.value.length) || !activeChannelId.value)
    return;
  if (uiFlags.value.isSending) return;
  const channelId = activeChannelId.value;
  const payload = {
    channelId,
    content,
    attachments: attachedFiles.value,
    mentionedUserIds: validMentionIds(content),
    replyToId: replyingTo.value?.id || null,
    echoId: getUuid(),
  };
  stopTyping();
  // Fase 1.5: optimistic — the store inserts the bubble synchronously, so we
  // clear the composer right away. A failure flips the bubble to "failed" with
  // a retry affordance (no data is lost), so no alert is needed here.
  const promise = store.dispatch('internalChat/sendMessage', payload);
  clearDraft(channelId);
  resetComposer();
  scrollToBottom();
  try {
    await promise;
  } catch (error) {
    // Handled on the message bubble (status: 'failed').
  }
};

// Re-send a message that failed (text + mentions; reuses the echo id so the
// failed bubble reconciles in place). Attachments are not carried on retry.
const retryMessage = message => {
  if (!activeChannelId.value) return;
  store.dispatch('internalChat/sendMessage', {
    channelId: activeChannelId.value,
    content: message.content,
    mentionedUserIds: message.mentioned_user_ids || [],
    echoId: message.echo_id || message.id,
  });
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

// Per-message action toolbar. Opened by the hover "⋯" button (also keyboard
// focusable), right-click, or a long-press on touch devices.
const actionMenuId = ref(null);
const openMessageMenu = msg => {
  reactionPickerId.value = null;
  confirmDeleteId.value = null;
  actionMenuId.value = actionMenuId.value === msg.id ? null : msg.id;
};

// Fase 1.2: long-press opens the action menu on touch (no right-click there).
let longPressTimer = null;
const startLongPress = msg => {
  clearTimeout(longPressTimer);
  longPressTimer = setTimeout(() => openMessageMenu(msg), 450);
};
const cancelLongPress = () => clearTimeout(longPressTimer);

const startEdit = msg => {
  actionMenuId.value = null;
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
  try {
    await store.dispatch('internalChat/editMessage', {
      channelId: activeChannelId.value,
      messageId: msg.id,
      content,
    });
  } catch (error) {
    useAlert(t('INTERNAL_CHAT.ACTION_ERROR'));
  }
};

const askDelete = msg => {
  actionMenuId.value = null;
  reactionPickerId.value = null;
  confirmDeleteId.value = confirmDeleteId.value === msg.id ? null : msg.id;
};
const doDelete = async msg => {
  confirmDeleteId.value = null;
  try {
    await store.dispatch('internalChat/deleteMessage', {
      channelId: activeChannelId.value,
      messageId: msg.id,
    });
  } catch (error) {
    useAlert(t('INTERNAL_CHAT.ACTION_ERROR'));
  }
};

const toggleReactionPicker = msg => {
  actionMenuId.value = null;
  confirmDeleteId.value = null;
  reactionPickerId.value = reactionPickerId.value === msg.id ? null : msg.id;
};
const toggleReaction = async (msg, emoji) => {
  reactionPickerId.value = null;
  try {
    await store.dispatch('internalChat/reactToMessage', {
      channelId: activeChannelId.value,
      messageId: msg.id,
      emoji,
    });
  } catch (error) {
    useAlert(t('INTERNAL_CHAT.ACTION_ERROR'));
  }
};
const reactionEntries = msg => Object.entries(msg.reactions || {});
const iReacted = (msg, emoji) =>
  (msg.reactions?.[emoji] || []).map(Number).includes(currentUserId.value);

// --- reply / quote (Fase 2C) ------------------------------------------------
const startReply = msg => {
  actionMenuId.value = null;
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

// Fase 1.1: after a websocket recovery (or when the tab regains focus), any
// message/read that happened while the socket was down was never delivered.
// Re-fetch the channel list, and refresh the open thread only when the user is
// following the bottom (so we don't yank them out of history they scrolled to).
const resyncInternalChat = () => {
  store.dispatch('internalChat/fetchChannels');
  if (activeChannelId.value && distanceFromBottom() < 240) {
    store.dispatch('internalChat/fetchMessages', activeChannelId.value);
  }
};
const onVisibilityChange = () => {
  if (typeof document !== 'undefined' && !document.hidden) resyncInternalChat();
};

onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
  store.dispatch('teams/get');
  store.dispatch('agents/get'); // presence (availability_status)
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, resyncInternalChat);
  document.addEventListener('visibilitychange', onVisibilityChange);
});

// Ao sair da tela do chat, nenhum canal está "aberto" → todas as mensagens
// voltam a notificar (som/toast) mesmo trabalhando em outra parte do sistema.
onBeforeUnmount(() => {
  store.dispatch('internalChat/clearActiveChannel');
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, resyncInternalChat);
  document.removeEventListener('visibilitychange', onVisibilityChange);
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background">
    <!-- ============ Channel list ============ -->
    <!-- On mobile: list and thread swap full-screen; both show side-by-side ≥md -->
    <aside
      class="flex-col w-full md:w-80 h-full border-r border-n-weak flex-shrink-0 bg-n-solid-1"
      :class="activeChannelId ? 'hidden md:flex' : 'flex'"
    >
      <header
        class="flex items-center justify-between px-4 h-14 border-b border-n-weak flex-shrink-0"
      >
        <h1 class="text-base font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.TITLE') }}
        </h1>
        <div class="flex items-center gap-1">
          <button
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
            :class="
              asideView === 'search'
                ? 'bg-[rgb(45_196_111_/_0.14)] text-n-brand'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :title="t('INTERNAL_CHAT.SEARCH_MESSAGES')"
            @click="
              asideView === 'search' ? backToChannels() : openMessageSearch()
            "
          >
            <span class="i-lucide-search text-lg" />
          </button>
          <button
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
            :class="
              asideView === 'mentions'
                ? 'bg-[rgb(45_196_111_/_0.14)] text-n-brand'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :title="t('INTERNAL_CHAT.MENTIONS')"
            @click="
              asideView === 'mentions' ? backToChannels() : openMentions()
            "
          >
            <span class="i-lucide-at-sign text-lg" />
          </button>
          <button
            v-if="isAdmin"
            class="inline-flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
            :class="
              auditMode
                ? 'bg-[rgb(45_196_111_/_0.14)] text-n-brand'
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
          <div class="relative">
            <button
              class="inline-flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
              :class="
                showNotifSettings
                  ? 'bg-[rgb(45_196_111_/_0.14)] text-n-brand'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
              :title="t('INTERNAL_CHAT.NOTIFICATIONS.TITLE')"
              @click="showNotifSettings = !showNotifSettings"
            >
              <span class="i-lucide-bell text-lg" />
            </button>
            <template v-if="showNotifSettings">
              <div
                class="fixed inset-0 z-10"
                @click="showNotifSettings = false"
              />
              <div
                class="absolute ltr:right-0 rtl:left-0 top-10 z-20 w-64 bg-n-solid-1 border border-n-weak rounded-xl shadow-lg overflow-hidden"
              >
                <div class="px-4 py-3 border-b border-n-weak">
                  <h3 class="text-sm font-semibold text-n-slate-12">
                    {{ t('INTERNAL_CHAT.NOTIFICATIONS.TITLE') }}
                  </h3>
                  <p class="mt-0.5 text-xs leading-snug text-n-slate-10">
                    {{ t('INTERNAL_CHAT.NOTIFICATIONS.SUBTITLE') }}
                  </p>
                </div>
                <div class="p-1.5">
                  <button
                    type="button"
                    role="switch"
                    :aria-checked="desktopNotifications"
                    class="flex w-full items-start gap-3 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-n-alpha-1"
                    @click="toggleDesktopNotifications"
                  >
                    <span
                      class="i-lucide-monitor mt-0.5 shrink-0 text-base text-n-slate-10"
                    />
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm font-medium text-n-slate-12">
                        {{ t('INTERNAL_CHAT.NOTIFICATIONS.DESKTOP') }}
                      </span>
                      <span
                        class="mt-0.5 block text-[11px] leading-snug text-n-slate-10"
                      >
                        {{ t('INTERNAL_CHAT.NOTIFICATIONS.DESKTOP_HINT') }}
                      </span>
                    </span>
                    <span
                      class="relative mt-0.5 inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors"
                      :class="
                        desktopNotifications ? 'bg-n-brand' : 'bg-n-slate-4'
                      "
                    >
                      <span
                        class="inline-block h-4 w-4 rounded-full bg-white shadow transition-transform"
                        :class="
                          desktopNotifications
                            ? 'translate-x-4'
                            : 'translate-x-0.5'
                        "
                      />
                    </span>
                  </button>
                  <button
                    type="button"
                    role="switch"
                    :aria-checked="soundNotifications"
                    class="flex w-full items-start gap-3 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-n-alpha-1"
                    @click="toggleSoundNotifications"
                  >
                    <span
                      class="i-lucide-volume-2 mt-0.5 shrink-0 text-base text-n-slate-10"
                    />
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm font-medium text-n-slate-12">
                        {{ t('INTERNAL_CHAT.NOTIFICATIONS.SOUND') }}
                      </span>
                      <span
                        class="mt-0.5 block text-[11px] leading-snug text-n-slate-10"
                      >
                        {{ t('INTERNAL_CHAT.NOTIFICATIONS.SOUND_HINT') }}
                      </span>
                    </span>
                    <span
                      class="relative mt-0.5 inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors"
                      :class="
                        soundNotifications ? 'bg-n-brand' : 'bg-n-slate-4'
                      "
                    >
                      <span
                        class="inline-block h-4 w-4 rounded-full bg-white shadow transition-transform"
                        :class="
                          soundNotifications
                            ? 'translate-x-4'
                            : 'translate-x-0.5'
                        "
                      />
                    </span>
                  </button>
                </div>
                <p
                  v-if="desktopPermissionBlocked"
                  class="px-4 pb-3 text-[11px] leading-snug text-n-ruby-11"
                >
                  {{ t('INTERNAL_CHAT.NOTIFICATIONS.BLOCKED') }}
                </p>
              </div>
            </template>
          </div>
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
        v-if="asideView === 'channels' && newPanel"
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

      <!-- Search (Fase 0.4) -->
      <div
        v-if="
          asideView === 'channels' &&
          !uiFlags.channelsLoadError &&
          (channelList.length || channelSearch)
        "
        class="px-3 pt-2 pb-1 flex-shrink-0"
      >
        <div class="relative">
          <span
            class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 pointer-events-none"
          />
          <!-- reset-base opts out of the global input padding rule (which would
               otherwise beat pl-9 on specificity and hide the icon). -->
          <input
            v-model="channelSearch"
            type="text"
            :placeholder="t('INTERNAL_CHAT.SEARCH_PLACEHOLDER')"
            class="reset-base w-full h-8 pl-9 pr-3 text-sm rounded-lg bg-n-alpha-1 border border-transparent focus:border-n-weak focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 outline-none transition-colors"
          />
        </div>
      </div>

      <!-- Channels -->
      <div v-if="asideView === 'channels'" class="flex-1 overflow-y-auto py-1">
        <button
          v-for="channel in filteredChannelList"
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
                {{ channelPreview(channel) }}
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

        <!-- Skeleton while the first load is in flight (Fase 0.3) -->
        <div
          v-if="uiFlags.isFetchingChannels && !channelList.length"
          class="px-2 py-1 space-y-1"
        >
          <div
            v-for="n in 6"
            :key="n"
            class="flex items-center gap-3 px-1 py-2.5"
          >
            <span
              class="w-[38px] h-[38px] rounded-full bg-n-alpha-2 animate-pulse flex-shrink-0"
            />
            <span class="flex-1 min-w-0 space-y-1.5">
              <span
                class="block h-3 w-1/2 rounded bg-n-alpha-2 animate-pulse"
              />
              <span
                class="block h-2.5 w-3/4 rounded bg-n-alpha-1 animate-pulse"
              />
            </span>
          </div>
        </div>

        <!-- Load error with retry (Fase 0.3) -->
        <div
          v-if="uiFlags.channelsLoadError && !uiFlags.isFetchingChannels"
          class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
        >
          <span class="i-lucide-cloud-off text-3xl mb-2 opacity-70" />
          <p class="text-sm">{{ t('INTERNAL_CHAT.LOAD_ERROR') }}</p>
          <button
            class="mt-3 inline-flex items-center gap-1.5 px-3 h-8 rounded-lg text-sm font-medium text-n-brand hover:bg-n-alpha-2 transition-colors"
            @click="retryFetchChannels"
          >
            <span class="i-lucide-refresh-cw text-sm" />
            {{ t('INTERNAL_CHAT.RETRY') }}
          </button>
        </div>

        <!-- No search matches (Fase 0.4) -->
        <div
          v-if="
            !filteredChannelList.length &&
            channelSearch &&
            !uiFlags.isFetchingChannels &&
            !uiFlags.channelsLoadError
          "
          class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
        >
          <span class="i-lucide-search-x text-3xl mb-2 opacity-70" />
          <p class="text-sm">{{ t('INTERNAL_CHAT.NO_SEARCH_RESULTS') }}</p>
        </div>

        <!-- Nothing yet -->
        <div
          v-if="
            !channelList.length &&
            !channelSearch &&
            !uiFlags.isFetchingChannels &&
            !uiFlags.channelsLoadError
          "
          class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
        >
          <span class="i-lucide-messages-square text-3xl mb-2 opacity-70" />
          <p class="text-sm">{{ t('INTERNAL_CHAT.EMPTY') }}</p>
        </div>
      </div>

      <!-- Fase 3: mentions inbox / message search -->
      <div v-if="asideView !== 'channels'" class="flex flex-col flex-1 min-h-0">
        <div class="flex items-center gap-2 px-3 pt-2 pb-1 flex-shrink-0">
          <button
            class="inline-flex items-center justify-center w-7 h-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
            :aria-label="t('INTERNAL_CHAT.BACK')"
            @click="backToChannels"
          >
            <span class="i-lucide-arrow-left text-base rtl:rotate-180" />
          </button>
          <span class="text-sm font-medium text-n-slate-12">
            {{
              asideView === 'mentions'
                ? t('INTERNAL_CHAT.MENTIONS')
                : t('INTERNAL_CHAT.SEARCH_MESSAGES')
            }}
          </span>
        </div>

        <div v-if="asideView === 'search'" class="px-3 pb-1 flex-shrink-0">
          <div class="relative">
            <span
              class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 pointer-events-none"
            />
            <input
              v-model="messageSearch"
              type="text"
              :placeholder="t('INTERNAL_CHAT.SEARCH_MESSAGES_PLACEHOLDER')"
              class="reset-base w-full h-8 pl-9 pr-3 text-sm rounded-lg bg-n-alpha-1 border border-transparent focus:border-n-weak focus:bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 outline-none transition-colors"
              @input="onMessageSearchInput"
            />
          </div>
        </div>

        <div class="flex-1 overflow-y-auto py-1">
          <button
            v-for="r in asideView === 'mentions' ? mentions : searchResults"
            :key="r.id"
            class="flex flex-col w-full px-3 py-2 text-left rounded-lg mx-1 hover:bg-n-alpha-1 transition-colors"
            @click="openResult(r)"
          >
            <span class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium text-n-slate-12 truncate">{{
                r.channel_title
              }}</span>
              <span class="text-[11px] text-n-slate-10 flex-shrink-0">{{
                timeLabel(r.created_at)
              }}</span>
            </span>
            <span class="block text-xs text-n-slate-10 truncate mt-0.5">
              <span class="text-n-slate-11">{{ r.user?.name }}:</span>
              {{ r.content || t('INTERNAL_CHAT.ATTACHMENT') }}
            </span>
          </button>

          <div
            v-if="uiFlags.isFetchingMentions || uiFlags.isSearching"
            class="px-4 py-6 text-center text-sm text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.LOADING') }}
          </div>
          <div
            v-else-if="asideView === 'mentions' && !mentions.length"
            class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
          >
            <span class="i-lucide-at-sign text-3xl mb-2 opacity-70" />
            <p class="text-sm">{{ t('INTERNAL_CHAT.NO_MENTIONS') }}</p>
          </div>
          <div
            v-else-if="
              asideView === 'search' && messageSearch.trim().length < 2
            "
            class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
          >
            <span class="i-lucide-search text-3xl mb-2 opacity-70" />
            <p class="text-sm">{{ t('INTERNAL_CHAT.SEARCH_MIN_HINT') }}</p>
          </div>
          <div
            v-else-if="asideView === 'search' && !searchResults.length"
            class="flex flex-col items-center justify-center text-center px-6 py-12 text-n-slate-10"
          >
            <span class="i-lucide-search-x text-3xl mb-2 opacity-70" />
            <p class="text-sm">{{ t('INTERNAL_CHAT.NO_RESULTS') }}</p>
          </div>
        </div>
      </div>
    </aside>

    <!-- ============ Thread ============ -->
    <section
      class="flex-col flex-1 h-full min-w-0"
      :class="activeChannelId ? 'flex' : 'hidden md:flex'"
    >
      <template v-if="activeChannel">
        <header
          class="flex items-center gap-3 px-5 h-14 border-b border-n-weak flex-shrink-0"
        >
          <button
            class="md:hidden inline-flex items-center justify-center w-8 h-8 -ml-2 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 flex-shrink-0"
            :aria-label="t('INTERNAL_CHAT.BACK')"
            @click="backToList"
          >
            <span class="i-lucide-arrow-left text-lg rtl:rotate-180" />
          </button>
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
                    @contextmenu.prevent="openMessageMenu(item.msg)"
                    @touchstart.passive="startLongPress(item.msg)"
                    @touchend="cancelLongPress"
                    @touchmove.passive="cancelLongPress"
                  >
                    <!-- hover / keyboard-focusable trigger (touch uses
                         long-press; desktop also keeps right-click) -->
                    <button
                      type="button"
                      class="absolute top-1/2 -translate-y-1/2 z-20 inline-flex items-center justify-center w-7 h-7 rounded-full bg-n-solid-1 border border-n-weak text-n-slate-11 shadow-sm opacity-0 transition-opacity group-hover:opacity-100 focus:opacity-100 focus-visible:opacity-100"
                      :class="isMine(item.msg) ? '-left-9' : '-right-9'"
                      :aria-label="t('INTERNAL_CHAT.MESSAGE_ACTIONS')"
                      @click.stop="openMessageMenu(item.msg)"
                    >
                      <span class="i-lucide-ellipsis text-base" />
                    </button>
                    <!-- click-outside backdrop for the action menu -->
                    <div
                      v-if="actionMenuId === item.msg.id"
                      class="fixed inset-0 z-10"
                      @click="actionMenuId = null"
                      @contextmenu.prevent="actionMenuId = null"
                    />
                    <!-- action toolbar — opened by right-click, floats fully
                         above the bubble so it never overlaps the text -->
                    <div
                      v-if="actionMenuId === item.msg.id"
                      class="absolute bottom-full mb-1.5 z-20 flex items-center gap-1 bg-n-solid-1 border border-n-weak rounded-full shadow-lg px-1.5 py-1.5"
                      :class="isMine(item.msg) ? 'right-0' : 'left-0'"
                    >
                      <button
                        class="inline-flex items-center justify-center w-9 h-9 rounded-full text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
                        :title="t('INTERNAL_CHAT.REPLY')"
                        @click="startReply(item.msg)"
                      >
                        <span class="i-lucide-reply text-xl" />
                      </button>
                      <button
                        class="inline-flex items-center justify-center w-9 h-9 rounded-full text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
                        :title="t('INTERNAL_CHAT.REACT')"
                        @click="toggleReactionPicker(item.msg)"
                      >
                        <span class="i-lucide-smile-plus text-xl" />
                      </button>
                      <button
                        v-if="isMine(item.msg)"
                        class="inline-flex items-center justify-center w-9 h-9 rounded-full text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
                        :title="t('INTERNAL_CHAT.EDIT')"
                        @click="startEdit(item.msg)"
                      >
                        <span class="i-lucide-pencil text-xl" />
                      </button>
                      <button
                        v-if="isMine(item.msg)"
                        class="inline-flex items-center justify-center w-9 h-9 rounded-full text-n-slate-12 hover:bg-n-ruby-3 hover:text-n-ruby-11 transition-colors"
                        :title="t('INTERNAL_CHAT.DELETE')"
                        @click="askDelete(item.msg)"
                      >
                        <span class="i-lucide-trash-2 text-xl" />
                      </button>
                    </div>

                    <!-- click-outside backdrop: close the reaction picker -->
                    <div
                      v-if="reactionPickerId === item.msg.id"
                      class="fixed inset-0 z-10"
                      @click="reactionPickerId = null"
                    />
                    <!-- reaction picker — floats above the bubble like the
                         action toolbar (which is hidden while this is open) -->
                    <div
                      v-if="reactionPickerId === item.msg.id"
                      class="absolute bottom-full mb-1.5 z-20 flex gap-1 bg-n-solid-1 border border-n-weak rounded-full shadow-md px-2 py-1"
                      :class="isMine(item.msg) ? 'right-0' : 'left-0'"
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
                        <span
                          v-else-if="part.t === 'mention'"
                          class="font-semibold rounded px-0.5"
                          :class="
                            isMine(item.msg)
                              ? 'bg-white/25'
                              : 'bg-n-brand/15 text-n-brand'
                          "
                          >{{ part.v }}</span
                        >
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

                  <div
                    class="flex items-center gap-1 mt-0.5 px-1 text-[10px] text-n-slate-9"
                    :class="isMine(item.msg) ? 'justify-end' : 'justify-start'"
                  >
                    <span
                      class="opacity-0 group-hover:opacity-100 transition-opacity"
                      >{{ timeLabel(item.msg.created_at) }}</span
                    >
                    <span
                      v-if="isMine(item.msg) && item.msg.status === 'progress'"
                      class="i-lucide-clock"
                      :title="t('INTERNAL_CHAT.SENDING')"
                    />
                    <button
                      v-else-if="
                        isMine(item.msg) && item.msg.status === 'failed'
                      "
                      class="font-medium text-n-ruby-11 hover:underline"
                      @click="retryMessage(item.msg)"
                    >
                      {{ t('INTERNAL_CHAT.SEND_FAILED_RETRY') }}
                    </button>
                  </div>
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

          <template v-if="showMentionPicker && filteredMentionMembers.length">
            <!-- click-outside backdrop: dismiss the picker without choosing -->
            <div
              class="fixed inset-0 z-10"
              @click="showMentionPicker = false"
            />
            <div
              class="absolute bottom-16 left-4 w-56 max-h-48 overflow-y-auto bg-n-solid-1 border border-n-weak rounded-lg shadow-lg z-20"
            >
              <button
                v-for="member in filteredMentionMembers"
                :key="member.id"
                class="flex items-center gap-2 w-full px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
                @click="applyMention(member)"
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
          </template>

          <template v-if="showEmoji">
            <!-- click-outside backdrop: close the emoji picker without picking -->
            <div class="fixed inset-0 z-10" @click="showEmoji = false" />
            <div class="absolute bottom-16 left-4 z-20">
              <EmojiPicker class="!static" @select="onEmojiSelect" />
            </div>
          </template>

          <!-- WhatsApp-style composer: tool cluster + input live inside one
               rounded pill, the round send button sits outside on the right,
               vertically centered with the input pill. -->
          <div class="flex items-center gap-2">
            <div
              class="flex flex-1 items-center gap-0.5 bg-n-alpha-1 border border-n-weak rounded-2xl px-1.5 py-1 focus-within:border-n-brand focus-within:bg-n-background transition-colors"
            >
              <button
                class="inline-flex items-center justify-center h-9 w-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors flex-shrink-0"
                :title="t('INTERNAL_CHAT.EMOJI')"
                @click="showEmoji = !showEmoji"
              >
                <span class="i-lucide-smile text-lg" />
              </button>
              <button
                class="inline-flex items-center justify-center h-9 w-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors flex-shrink-0"
                :title="t('INTERNAL_CHAT.ATTACH')"
                @click="onPickFile"
              >
                <span class="i-lucide-paperclip text-lg" />
              </button>
              <button
                v-if="channelMembers.length"
                class="inline-flex items-center justify-center h-9 w-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors flex-shrink-0"
                :title="t('INTERNAL_CHAT.MENTION')"
                @click="openMentionPicker"
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
                class="flex-1 resize-none bg-transparent px-2 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none max-h-[140px] leading-relaxed"
                :placeholder="t('INTERNAL_CHAT.PLACEHOLDER')"
                @input="onComposerInput"
                @keydown.enter.exact.prevent="send"
              />
            </div>
            <button
              class="inline-flex items-center justify-center h-10 w-10 rounded-full text-white bg-n-brand shadow-sm hover:bg-n-brand-hover disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none transition-all flex-shrink-0"
              :title="t('INTERNAL_CHAT.SEND')"
              :disabled="
                (!draft.trim() && !attachedFiles.length) || uiFlags.isSending
              "
              @click="send"
            >
              <span class="i-lucide-send-horizontal text-lg" />
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
