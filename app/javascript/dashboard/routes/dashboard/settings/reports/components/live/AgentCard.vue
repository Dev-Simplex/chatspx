<script setup>
import { computed } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import ConversationItem from './ConversationItem.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
  isConversationsLoading: {
    type: Boolean,
    default: false,
  },
  conversationsLoaded: {
    type: Boolean,
    default: false,
  },
  hasMoreConversations: {
    type: Boolean,
    default: false,
  },
});
const emit = defineEmits(['loadMoreConversations']);

const statusConfig = computed(() => {
  const status = props.agent.status || 'offline';
  const configs = {
    online: {
      label: 'Online',
      class: 'bg-n-brand/10 text-n-brand',
      dotClass: 'bg-n-brand',
    },
    busy: {
      label: 'Ausente',
      class: 'bg-n-amber-3 text-n-amber-11',
      dotClass: 'bg-n-amber-10',
    },
    offline: {
      label: 'Offline',
      class: 'bg-n-slate-3 text-n-slate-11',
      dotClass: 'bg-n-slate-10',
    },
  };
  return configs[status] || configs.offline;
});

const totalOpenCalls = computed(() => props.agent.totalOpenCalls || 0);

const loadMoreConversations = () => {
  emit('loadMoreConversations');
};
</script>

<template>
  <div
    class="flex flex-col h-[400px] bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden transition-all duration-300 hover:shadow-lg"
  >
    <div
      class="flex items-center gap-3 p-4 border-b border-n-weak bg-n-alpha-2 flex-shrink-0"
    >
      <Avatar
        :name="agent.name"
        :src="agent.avatar"
        :size="40"
        :status="agent.status"
        rounded-full
      />
      <div class="flex-1 min-w-0">
        <h5 class="text-base font-medium text-n-slate-12 m-0 truncate">
          {{ agent.name }}
        </h5>
        <div class="flex items-center gap-2 mt-1">
          <span
            class="flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium transition-all"
            :class="statusConfig.class"
          >
            <span class="size-2 rounded-full" :class="statusConfig.dotClass" />
            {{ statusConfig.label }}
          </span>
        </div>
      </div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto">
      <div
        v-if="
          isConversationsLoading &&
          (!agent.conversations || !agent.conversations.length)
        "
        class="flex items-center justify-center p-8 text-center h-full"
      >
        <p class="text-sm text-n-slate-11 m-0">
          {{ $t('LIVE_REPORTS.IN_SERVICE.LOADING') }}
        </p>
      </div>
      <div v-if="agent.conversations && agent.conversations.length > 0">
        <ConversationItem
          v-for="(conversation, index) in agent.conversations"
          :key="conversation.id"
          :conversation="conversation"
          :style="{ animationDelay: `${index * 0.05}s` }"
        />
        <div v-if="hasMoreConversations" class="px-3 pb-3 pt-1">
          <button
            type="button"
            class="w-full text-xs font-medium text-n-brand-11 hover:text-n-brand-12 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 disabled:opacity-60 disabled:cursor-not-allowed"
            :disabled="isConversationsLoading"
            @click="loadMoreConversations"
          >
            {{
              isConversationsLoading
                ? $t('LIVE_REPORTS.IN_SERVICE.LOADING')
                : $t('LIVE_REPORTS.IN_SERVICE.LOAD_MORE_CONVERSATIONS')
            }}
          </button>
        </div>
      </div>
      <div
        v-else-if="conversationsLoaded"
        class="flex items-center justify-center p-8 text-center h-full"
      >
        <p class="text-sm text-n-slate-11 m-0">
          {{ $t('LIVE_REPORTS.IN_SERVICE.NO_CONVERSATIONS') }}
        </p>
      </div>
    </div>
    <div
      class="p-4 border-t border-n-weak bg-n-alpha-2 flex-shrink-0 flex items-center justify-between gap-2"
    >
      <p
        class="text-sm font-medium text-n-slate-12 m-0 flex items-center gap-2"
      >
        <span class="i-lucide-phone-call size-4 text-n-brand" />
        {{ $t('LIVE_REPORTS.IN_SERVICE.AGENT_CARD.TOTAL_OPEN_CALLS') }}:
      </p>
      <span
        class="flex items-center justify-center min-w-[1.75rem] h-7 px-2 rounded-lg font-semibold bg-n-brand/10 text-n-brand text-sm tabular-nums"
      >
        {{ totalOpenCalls }}
      </span>
    </div>
  </div>
</template>
