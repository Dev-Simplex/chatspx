<script setup>
import {
  ref,
  computed,
  onMounted,
  nextTick,
  watch,
  defineAsyncComponent,
} from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { messageStamp } from 'shared/helpers/timeHelper';

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const store = useStore();
const { t } = useI18n();

const channels = useMapGetter('internalChat/getChannels');
const agents = useMapGetter('internalChat/getAgents');
const uiFlags = useMapGetter('internalChat/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');
const teams = useMapGetter('teams/getMyTeams');

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

// New-channel panel: null | 'menu' | 'dm' | 'group' | 'team'
const newPanel = ref(null);
const groupName = ref('');
const groupMemberIds = ref([]);

const activeChannel = computed(() =>
  channels.value.find(c => c.id === activeChannelId.value)
);
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

const URL_RE = /(https?:\/\/[^\s]+)/g;
const textParts = content => {
  const s = String(content || '');
  const out = [];
  let last = 0;
  s.replace(URL_RE, (match, _g, idx) => {
    if (idx > last) out.push({ t: 'text', v: s.slice(last, idx) });
    out.push({ t: 'link', v: match });
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

const onThreadScroll = () => {
  showScrollDown.value = distanceFromBottom() > 240;
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
  nextTick(autoResize);
};

const openChannel = async channel => {
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
  };
  resetComposer();
  await store.dispatch('internalChat/sendMessage', payload);
  scrollToBottom();
};

const isMine = message => message.user?.id === currentUserId.value;
const mentionsMe = message =>
  (message.mentioned_user_ids || []).map(Number).includes(currentUserId.value);

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
        <button
          class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
          :title="t('INTERNAL_CHAT.NEW_DM')"
          @click="newPanel = newPanel ? null : 'menu'"
        >
          <span class="i-lucide-plus text-lg" />
        </button>
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
          v-for="channel in channels"
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
          v-if="!channels.length && !uiFlags.isFetchingChannels"
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
            rounded-full
          />
          <div class="min-w-0">
            <h2
              class="text-sm font-semibold text-n-slate-12 truncate leading-tight"
            >
              {{ activeChannel.title }}
            </h2>
            <p class="text-xs text-n-slate-10 truncate leading-tight">
              {{ channelSubtitle(activeChannel) }}
            </p>
          </div>
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
                  class="group max-w-[68%] flex flex-col"
                  :class="isMine(item.msg) ? 'items-end' : 'items-start'"
                >
                  <span
                    v-if="item.showHeader && !isMine(item.msg)"
                    class="text-xs font-medium text-n-slate-11 mb-0.5 px-1"
                  >
                    {{ item.msg.user?.name }}
                  </span>
                  <div
                    class="px-3 py-2 rounded-2xl text-sm break-words"
                    :class="[
                      isMine(item.msg)
                        ? 'bg-n-brand text-white rounded-br-sm'
                        : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm',
                      mentionsMe(item.msg) ? 'ring-2 ring-n-brand/60' : '',
                    ]"
                  >
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
                        <template v-else>{{ part.v }}</template>
                      </template>
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
                  </div>
                  <span
                    class="text-[10px] text-n-slate-9 mt-0.5 px-1 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    {{ timeLabel(item.msg.created_at) }}
                  </span>
                </div>
              </div>
            </template>
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

        <!-- Composer -->
        <footer class="px-4 py-3 border-t border-n-weak relative flex-shrink-0">
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
              @input="autoResize"
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
  </div>
</template>
