<script setup>
import { ref, computed, onMounted, nextTick, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const store = useStore();
const { t } = useI18n();

const channels = useMapGetter('internalChat/getChannels');
const agents = useMapGetter('internalChat/getAgents');
const uiFlags = useMapGetter('internalChat/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');

const activeChannelId = ref(null);
const draft = ref('');
const showNewDm = ref(false);
const threadRef = ref(null);

const activeChannel = computed(() =>
  channels.value.find(c => c.id === activeChannelId.value)
);
const messages = computed(() =>
  store.getters['internalChat/getMessages'](activeChannelId.value)
);

const scrollToBottom = async () => {
  await nextTick();
  if (threadRef.value) threadRef.value.scrollTop = threadRef.value.scrollHeight;
};

const openChannel = async channel => {
  activeChannelId.value = channel.id;
  await store.dispatch('internalChat/fetchMessages', channel.id);
  scrollToBottom();
};

const startDm = async agent => {
  const channel = await store.dispatch('internalChat/createDm', agent.id);
  showNewDm.value = false;
  if (channel) openChannel(channel);
};

const send = async () => {
  const content = draft.value.trim();
  if (!content || !activeChannelId.value) return;
  draft.value = '';
  await store.dispatch('internalChat/sendMessage', {
    channelId: activeChannelId.value,
    content,
  });
  scrollToBottom();
};

const isMine = message => message.user?.id === currentUserId.value;

watch(messages, scrollToBottom);

onMounted(() => {
  store.dispatch('internalChat/fetchChannels');
  store.dispatch('internalChat/fetchAgents');
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
          @click="showNewDm = !showNewDm"
        >
          <span class="i-lucide-plus text-lg" />
        </button>
      </header>

      <!-- New DM picker -->
      <div
        v-if="showNewDm"
        class="border-b border-n-weak max-h-64 overflow-y-auto"
      >
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
            class="flex items-center justify-center w-9 h-9 rounded-full bg-n-alpha-2 text-n-slate-11 flex-shrink-0 i-lucide-user-round"
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
              :class="
                isMine(message)
                  ? 'bg-n-brand text-white rounded-br-sm'
                  : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm'
              "
            >
              <p
                v-if="!isMine(message)"
                class="text-xs font-medium text-n-slate-10 mb-0.5"
              >
                {{ message.user?.name }}
              </p>
              <p class="whitespace-pre-wrap break-words">
                {{ message.content }}
              </p>
            </div>
          </div>
        </div>

        <footer class="px-4 py-3 border-t border-n-weak">
          <div class="flex items-end gap-2">
            <textarea
              v-model="draft"
              rows="1"
              class="flex-1 resize-none px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg focus:outline-none focus:border-n-brand"
              :placeholder="t('INTERNAL_CHAT.PLACEHOLDER')"
              @keydown.enter.exact.prevent="send"
            />
            <button
              class="inline-flex items-center justify-center h-9 px-4 text-sm font-medium text-white bg-n-brand rounded-lg disabled:opacity-50"
              :disabled="!draft.trim() || uiFlags.isSending"
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
