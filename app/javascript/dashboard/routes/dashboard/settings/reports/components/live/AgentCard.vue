<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import ConversationItem from './ConversationItem.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const statusConfig = computed(() => {
  const status = props.agent.status || 'offline';
  const configs = {
    online: {
      label: 'Online',
      class: 'bg-n-teal-3 text-n-teal-11',
      dotClass: 'bg-n-teal-10',
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
</script>

<template>
  <div
    class="flex flex-col h-[400px] bg-n-solid-2 rounded-xl shadow outline-1 outline outline-n-container overflow-hidden transition-all duration-300 hover:shadow-lg hover:outline-n-brand/20"
  >
    <div class="flex items-center gap-3 p-4 border-b border-n-weak bg-n-alpha-2 flex-shrink-0">
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
            <span
              class="w-1.5 h-1.5 rounded-full animate-pulse"
              :class="statusConfig.dotClass"
            />
            {{ statusConfig.label }}
          </span>
        </div>
      </div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scrollbar-thin scrollbar-thumb-n-weak scrollbar-track-transparent">
      <div v-if="agent.conversations && agent.conversations.length > 0">
        <ConversationItem
          v-for="(conversation, index) in agent.conversations"
          :key="conversation.id"
          :conversation="conversation"
          :style="{ animationDelay: `${index * 0.05}s` }"
        />
      </div>
      <div
        v-else
        class="flex items-center justify-center p-8 text-center h-full"
      >
        <p class="text-sm text-n-slate-11 m-0">
          {{ $t('LIVE_REPORTS.IN_SERVICE.NO_CONVERSATIONS') }}
        </p>
      </div>
    </div>
    <div class="p-4 border-t border-n-weak bg-n-alpha-2 flex-shrink-0 flex items-center justify-between gap-2">
      <p class="text-sm font-medium text-n-slate-12 m-0 flex items-center gap-2">
        <span class="i-lucide-phone-call size-4 text-n-brand" />
        {{ $t('LIVE_REPORTS.IN_SERVICE.AGENT_CARD.TOTAL_OPEN_CALLS') }}:
      </p>
      <span
        class="flex items-center justify-center min-w-[1.75rem] h-7 px-2 rounded-lg font-semibold text-n-slate-12 bg-n-brand-3 text-n-brand-11 text-sm"
      >
        {{ totalOpenCalls }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.scrollbar-thin {
  scrollbar-width: thin;
}

.scrollbar-thin::-webkit-scrollbar {
  width: 4px;
}

.scrollbar-thin::-webkit-scrollbar-track {
  background: transparent;
}

.scrollbar-thin::-webkit-scrollbar-thumb {
  background-color: rgba(148, 163, 184, 0.3);
  border-radius: 2px;
}

.scrollbar-thin::-webkit-scrollbar-thumb:hover {
  background-color: rgba(148, 163, 184, 0.5);
}
</style>
