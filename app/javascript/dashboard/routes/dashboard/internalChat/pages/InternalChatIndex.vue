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

const channelIcon = channel => {
  if (channel.channel_type === 'team') return 'i-lucide-users-round';
  if (channel.channel_type === 'group_chat') return 'i-lucide-users';
  return 'i-lucide-user-round';
};

const scrollToBottom = async () => {
  await nextTick();
  if (threadRef.value) threadRef.value.scrollTop = threadRef.value.scrollHeight;
};

const resetComposer = () => {
  draft.value = '';
  attachedFiles.value = [];
  mentionedUserIds.value = [];
  showEmoji.value = false;
  showMentionPicker.value = false;
};

const openChannel = async channel => {
  activeChannelId.value = channel.id;
  resetComposer();
  await store.dispatch('internalChat/fetchMessages', channel.id);
  scrollToBottom();
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

// Composer actions
const onEmojiSelect = emoji => {
  draft.value += emoji;
  showEmoji.value = false;
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

watch(messages, scrollToBottom);

onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
  store.dispatch('teams/get');
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background">
    <!-- Channel list -->
    <aside
      class="flex flex-col w-80 h-full border-r border-n-weak flex-shrink-0"
    >
      <header
        class="flex items-center justify-between px-4 h-14 border-b border-n-weak"
      >
        <h1 class="text-base font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.TITLE') }}
        </h1>
        <button
          class="inline-flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          :title="t('INTERNAL_CHAT.NEW_DM')"
          @click="newPanel = newPanel ? null : 'menu'"
        >
          <span class="i-lucide-plus text-lg" />
        </button>
      </header>

      <!-- New-channel panel -->
      <div
        v-if="newPanel"
        class="border-b border-n-weak max-h-80 overflow-y-auto"
      >
        <!-- Menu -->
        <template v-if="newPanel === 'menu'">
          <button
            class="flex items-center gap-2 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'dm'"
          >
            <span class="i-lucide-user-round text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_DM') }}
          </button>
          <button
            class="flex items-center gap-2 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'group'"
          >
            <span class="i-lucide-users text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_GROUP') }}
          </button>
          <button
            class="flex items-center gap-2 w-full px-4 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="newPanel = 'team'"
          >
            <span class="i-lucide-users-round text-n-slate-10" />
            {{ t('INTERNAL_CHAT.NEW_TEAM_CHANNEL') }}
          </button>
        </template>

        <!-- DM picker -->
        <template v-else-if="newPanel === 'dm'">
          <p class="px-4 py-2 text-xs font-medium uppercase text-n-slate-10">
            {{ t('INTERNAL_CHAT.START_WITH') }}
          </p>
          <button
            v-for="agent in agents"
            :key="agent.id"
            class="flex items-center gap-2 w-full px-4 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="startDm(agent)"
          >
            <span class="i-lucide-user-round text-n-slate-10" />
            {{ agent.name }}
          </button>
          <p v-if="!agents.length" class="px-4 py-3 text-sm text-n-slate-10">
            {{ t('INTERNAL_CHAT.NO_AGENTS') }}
          </p>
        </template>

        <!-- Group form -->
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

        <!-- Team picker -->
        <template v-else-if="newPanel === 'team'">
          <p class="px-4 py-2 text-xs font-medium uppercase text-n-slate-10">
            {{ t('INTERNAL_CHAT.SELECT_TEAM') }}
          </p>
          <button
            v-for="team in teams"
            :key="team.id"
            class="flex items-center gap-2 w-full px-4 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
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

      <div class="flex-1 overflow-y-auto">
        <button
          v-for="channel in channels"
          :key="channel.id"
          class="flex items-center gap-3 w-full px-4 py-3 text-left hover:bg-n-alpha-1"
          :class="{ 'bg-n-alpha-2': channel.id === activeChannelId }"
          @click="openChannel(channel)"
        >
          <span
            class="flex items-center justify-center w-9 h-9 rounded-full bg-n-alpha-2 text-n-slate-11 flex-shrink-0"
            :class="channelIcon(channel)"
          />
          <span class="flex-1 min-w-0">
            <span class="flex items-center justify-between">
              <span class="text-sm font-medium text-n-slate-12 truncate">
                {{ channel.title }}
              </span>
              <span
                v-if="channel.unread_count"
                class="ml-2 inline-flex items-center justify-center min-w-5 h-5 px-1.5 text-xs font-medium text-white bg-n-brand rounded-full"
              >
                {{ channel.unread_count }}
              </span>
            </span>
            <span
              v-if="channel.last_message"
              class="block text-xs text-n-slate-10 truncate"
            >
              {{ channel.last_message.content }}
            </span>
          </span>
        </button>
        <p
          v-if="!channels.length && !uiFlags.isFetchingChannels"
          class="px-4 py-8 text-sm text-center text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.EMPTY') }}
        </p>
      </div>
    </aside>

    <!-- Thread -->
    <section class="flex flex-col flex-1 h-full min-w-0">
      <template v-if="activeChannel">
        <header class="flex items-center px-5 h-14 border-b border-n-weak">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ activeChannel.title }}
          </h2>
        </header>

        <div ref="threadRef" class="flex-1 overflow-y-auto px-5 py-4 space-y-3">
          <div
            v-for="message in messages"
            :key="message.id"
            class="flex"
            :class="isMine(message) ? 'justify-end' : 'justify-start'"
          >
            <div
              class="max-w-[70%] px-3 py-2 rounded-2xl text-sm"
              :class="[
                isMine(message)
                  ? 'bg-n-brand text-white rounded-br-sm'
                  : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm',
                mentionsMe(message) ? 'ring-2 ring-n-brand/60' : '',
              ]"
            >
              <p
                v-if="!isMine(message)"
                class="text-xs font-medium text-n-slate-10 mb-0.5"
              >
                {{ message.user?.name }}
              </p>
              <p v-if="message.content" class="whitespace-pre-wrap break-words">
                {{ message.content }}
              </p>
              <a
                v-for="attachment in message.attachments || []"
                :key="attachment.id"
                :href="attachment.url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-1.5 mt-1 text-xs underline opacity-90"
              >
                <span class="i-lucide-paperclip" />
                {{ attachment.filename }}
              </a>
            </div>
          </div>
        </div>

        <footer class="px-4 py-3 border-t border-n-weak relative">
          <!-- attachment chips -->
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

          <!-- mention picker -->
          <div
            v-if="showMentionPicker && channelMembers.length"
            class="absolute bottom-16 left-4 w-56 max-h-48 overflow-y-auto bg-n-background border border-n-weak rounded-lg shadow-lg z-10"
          >
            <button
              v-for="member in channelMembers"
              :key="member.id"
              class="flex items-center gap-2 w-full px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
              @click="mentionMember(member)"
            >
              <span class="i-lucide-at-sign text-n-slate-10" />
              {{ member.name }}
            </button>
          </div>

          <EmojiInput
            v-if="showEmoji"
            class="absolute bottom-16 right-4 z-10"
            :on-click="onEmojiSelect"
          />

          <div class="flex items-end gap-2">
            <button
              class="inline-flex items-center justify-center h-9 w-9 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('INTERNAL_CHAT.ATTACH')"
              @click="onPickFile"
            >
              <span class="i-lucide-paperclip text-lg" />
            </button>
            <button
              class="inline-flex items-center justify-center h-9 w-9 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="showEmoji = !showEmoji"
            >
              <span class="i-lucide-smile text-lg" />
            </button>
            <button
              v-if="channelMembers.length"
              class="inline-flex items-center justify-center h-9 w-9 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
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
              v-model="draft"
              rows="1"
              class="flex-1 resize-none px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg focus:outline-none focus:border-n-brand"
              :placeholder="t('INTERNAL_CHAT.PLACEHOLDER')"
              @keydown.enter.exact.prevent="send"
            />
            <button
              class="inline-flex items-center justify-center h-9 px-4 text-sm font-medium text-white bg-n-brand rounded-lg disabled:opacity-50"
              :disabled="
                (!draft.trim() && !attachedFiles.length) || uiFlags.isSending
              "
              @click="send"
            >
              {{ t('INTERNAL_CHAT.SEND') }}
            </button>
          </div>
        </footer>
      </template>

      <div
        v-else
        class="flex flex-col items-center justify-center flex-1 text-n-slate-10"
      >
        <span class="i-lucide-messages-square text-4xl mb-2" />
        <p class="text-sm">{{ t('INTERNAL_CHAT.SELECT_PROMPT') }}</p>
      </div>
    </section>
  </div>
</template>
