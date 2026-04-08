<script setup>
import { nextTick, ref, watch, computed } from 'vue';
import { useTrack } from 'dashboard/composables';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useUISettings } from 'dashboard/composables/useUISettings';

import CopilotInput from './CopilotInput.vue';
import CopilotLoader from './CopilotLoader.vue';
import CopilotAssistantMessage from './CopilotAssistantMessage.vue';
import CopilotThinkingGroup from './CopilotThinkingGroup.vue';
import CopilotToolCard from './CopilotToolCard.vue';
import ToggleCopilotAssistant from './ToggleCopilotAssistant.vue';
import CopilotQuickActions from './CopilotQuickActions.vue';

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  conversationInboxType: {
    type: String,
    required: true,
  },
  assistants: {
    type: Array,
    default: () => [],
  },
  activeAssistant: {
    type: Object,
    default: () => ({}),
  },
  isAwaitingResponse: {
    type: Boolean,
    default: false,
  },
  hasTimedOut: {
    type: Boolean,
    default: false,
  },
  timeoutMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['sendMessage', 'reset', 'setAssistant', 'retry']);

const sendMessage = message => {
  emit('sendMessage', message);
  useTrack(COPILOT_EVENTS.SEND_MESSAGE);
};

const chatContainer = ref(null);

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const groupedMessages = computed(() => {
  const result = [];
  let thinkingGroup = [];
  props.messages.forEach(message => {
    if (message.message_type === 'assistant_thinking') {
      thinkingGroup.push(message);
    } else {
      if (thinkingGroup.length > 0) {
        result.push({
          id: thinkingGroup[0].id,
          message_type: 'thinking_group',
          messages: thinkingGroup,
        });
        thinkingGroup = [];
      }
      result.push(message);
    }
  });
  if (thinkingGroup.length > 0) {
    result.push({
      id: thinkingGroup[0].id,
      message_type: 'thinking_group',
      messages: thinkingGroup,
    });
  }
  return result;
});

const isLastMessageFromAssistant = computed(() => {
  if (!groupedMessages.value.length) return false;
  return (
    groupedMessages.value[groupedMessages.value.length - 1].message_type ===
    'assistant'
  );
});

const hasAssistants = computed(() => props.assistants.length > 0);
const hasMessages = computed(() => props.messages.length > 0);

const shouldShowLoader = computed(() => {
  if (props.hasTimedOut) return false;
  if (props.isAwaitingResponse) return true;
  return hasMessages.value && !isLastMessageFromAssistant.value;
});

const { updateUISettings } = useUISettings();

const closeCopilotPanel = () => {
  updateUISettings({
    is_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });
};

const handleReset = () => {
  emit('reset');
};

const SUGGESTIONS = [
  { text: 'Resumir esta conversa', icon: 'i-lucide-file-text' },
  { text: 'Sugerir uma resposta', icon: 'i-lucide-message-circle' },
  { text: 'Quem deve atender?', icon: 'i-lucide-user-check' },
  { text: 'Histórico do contato', icon: 'i-lucide-clock' },
];

watch(
  [() => props.messages],
  () => {
    scrollToBottom();
  },
  { deep: true }
);
</script>

<template>
  <div
    class="flex h-full w-full flex-col text-sm leading-6 tracking-tight bg-white dark:bg-n-solid-1 ltr:border-l rtl:border-r border-n-weak"
  >
    <!-- Header: clean, sem gradient -->
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak bg-white dark:bg-n-solid-1"
    >
      <div class="flex items-center gap-2">
        <span class="i-woot-captain size-5 text-n-brand" />
        <div class="flex items-center gap-1.5">
          <!-- eslint-disable-next-line vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <span class="text-sm font-semibold text-n-slate-12">
            Copiloto IA
          </span>
          <!-- eslint-disable-next-line vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <span v-if="activeAssistant?.name" class="text-xs text-n-slate-10">
            · {{ activeAssistant.name }}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-0.5">
        <button
          class="flex items-center justify-center size-7 rounded-lg text-n-slate-10 transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="handleReset"
        >
          <i class="i-lucide-rotate-ccw size-3.5" />
        </button>
        <button
          class="flex items-center justify-center size-7 rounded-lg text-n-slate-10 transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="closeCopilotPanel"
        >
          <i class="i-lucide-x size-3.5" />
        </button>
      </div>
    </div>

    <!-- Chat area -->
    <div
      ref="chatContainer"
      class="flex-1 overflow-y-auto px-4 py-4 space-y-4 bg-n-background dark:bg-n-solid-1"
    >
      <!-- Messages -->
      <template v-if="hasMessages">
        <template v-for="(item, index) in groupedMessages" :key="item.id">
          <!-- User message -->
          <div v-if="item.message_type === 'user'" class="flex justify-end">
            <div
              class="max-w-[80%] rounded-2xl rounded-br-sm bg-n-brand/10 px-3 py-2 text-sm text-n-slate-12 break-words"
            >
              {{ item.message?.content || item.message }}
            </div>
          </div>

          <!-- Assistant message -->
          <div
            v-else-if="item.message_type === 'assistant'"
            class="flex items-start gap-2"
          >
            <span class="i-woot-captain mt-0.5 size-5 shrink-0 text-n-brand" />
            <div
              class="max-w-[85%] rounded-2xl rounded-bl-sm border border-n-weak/50 bg-white px-3 py-2 dark:bg-n-solid-3"
            >
              <CopilotAssistantMessage
                :message="item.message"
                :is-last-message="index === groupedMessages.length - 1"
                :conversation-inbox-type="conversationInboxType"
              />
            </div>
          </div>

          <!-- Tool call -->
          <CopilotToolCard
            v-else-if="item.message_type === 'tool_call'"
            :tool-name="item.tool_name"
            :is-loading="item.status === 'pending'"
            :result="item.result"
          />

          <!-- Thinking group -->
          <CopilotThinkingGroup
            v-else-if="item.message_type === 'thinking_group'"
            :messages="item.messages"
            :default-collapsed="isLastMessageFromAssistant"
          />
        </template>

        <!-- Timeout -->
        <div
          v-if="hasTimedOut"
          class="flex flex-col gap-2 rounded-lg border border-n-weak bg-n-alpha-2 p-3"
        >
          <p class="text-sm font-medium text-n-slate-12">
            {{ $t('CAPTAIN.COPILOT.RESPONSE_TIMEOUT_TITLE') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ timeoutMessage || $t('CAPTAIN.COPILOT.RESPONSE_TIMEOUT_BODY') }}
          </p>
          <div>
            <button
              class="rounded-md bg-n-alpha-2 px-3 py-1 text-xs font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-3"
              @click="$emit('retry')"
            >
              {{ $t('CAPTAIN.COPILOT.RETRY') }}
            </button>
          </div>
        </div>

        <!-- Loader -->
        <div v-else-if="shouldShowLoader" class="flex items-start gap-2">
          <span
            class="i-woot-captain mt-0.5 size-5 shrink-0 animate-pulse text-n-brand"
          />
          <CopilotLoader />
        </div>
      </template>

      <!-- Empty state -->
      <div
        v-else
        class="flex flex-1 flex-col items-center justify-center gap-5 px-4 h-full"
      >
        <span class="i-woot-captain size-10 text-n-brand opacity-80" />
        <div class="space-y-1 text-center">
          <!-- eslint-disable-next-line vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <p class="text-base font-semibold text-n-slate-12">
            Como posso ajudar?
          </p>
          <!-- eslint-disable-next-line vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <p class="text-xs text-n-slate-10">
            Posso resumir conversas, sugerir respostas e mais.
          </p>
        </div>
        <div v-if="hasAssistants" class="flex flex-wrap justify-center gap-2">
          <button
            v-for="suggestion in SUGGESTIONS"
            :key="suggestion.text"
            class="inline-flex items-center gap-1.5 rounded-full border border-n-weak px-3 py-1.5 text-xs text-n-slate-11 transition-all duration-200 hover:border-n-brand/30 hover:bg-n-brand/5 hover:text-n-brand dark:border-n-weak dark:text-n-slate-11 dark:hover:border-n-brand/30 dark:hover:bg-n-brand/5 dark:hover:text-n-brand"
            @click="sendMessage(suggestion.text)"
          >
            <i class="size-3 shrink-0" :class="suggestion.icon" />
            <span>{{ suggestion.text }}</span>
          </button>
        </div>
        <div v-else class="text-center">
          <p class="text-sm text-n-slate-11">
            {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div class="border-t border-n-weak bg-white px-4 py-3 dark:bg-n-solid-1">
      <ToggleCopilotAssistant
        v-if="assistants.length > 1"
        class="mb-2"
        :assistants="assistants"
        :active-assistant="activeAssistant"
        @set-assistant="$event => emit('setAssistant', $event)"
      />
      <CopilotQuickActions
        v-if="hasMessages"
        class="mb-2"
        @send="sendMessage"
      />
      <CopilotInput v-if="hasAssistants" class="w-full" @send="sendMessage" />
    </div>
  </div>
</template>
