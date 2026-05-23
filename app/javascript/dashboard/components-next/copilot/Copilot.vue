<script setup>
/* eslint-disable no-use-before-define, vue/no-undef-components */
import { nextTick, ref, watch, computed } from 'vue';
import { useTrack } from 'dashboard/composables';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useUISettings } from 'dashboard/composables/useUISettings';

import CopilotInput from './CopilotInput.vue';
import CopilotLoader from './CopilotLoader.vue';
import CopilotAgentMessage from './CopilotAgentMessage.vue';
import CopilotAssistantMessage from './CopilotAssistantMessage.vue';
import CopilotThinkingGroup from './CopilotThinkingGroup.vue';
import ToggleCopilotAssistant from './ToggleCopilotAssistant.vue';
import CopilotEmptyState from './CopilotEmptyState.vue';
import Icon from '../icon/Icon.vue';
import CopilotQuickActions from './CopilotQuickActions.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import { useI18n } from 'vue-i18n';

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

const { t } = useI18n();

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

const handleSidebarAction = action => {
  if (action === 'reset') {
    emit('reset');
  }
};

const hasAssistants = computed(() => props.assistants.length > 0);
const hasMessages = computed(() => props.messages.length > 0);
const copilotButtons = computed(() => {
  if (hasMessages.value) {
    return [
      {
        key: 'reset',
        icon: 'i-lucide-refresh-ccw',
        tooltip: t('CAPTAIN.COPILOT.RESET'),
      },
    ];
  }
  return [];
});

const statusLabel = computed(() => {
  if (props.hasTimedOut) return t('CAPTAIN.COPILOT.STATUS_OFFLINE');
  if (shouldShowLoader.value) return t('CAPTAIN.COPILOT.STATUS_THINKING');
  return t('CAPTAIN.COPILOT.STATUS_READY');
});

const statusDotColor = computed(() => {
  if (props.hasTimedOut) return 'bg-n-slate-9';
  if (shouldShowLoader.value) return 'bg-n-amber-9 animate-pulse';
  return 'bg-n-teal-9';
});
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
    class="flex flex-col h-full text-sm leading-6 tracking-tight w-full bg-n-solid-1 ltr:border-l rtl:border-r border-n-weak"
  >
    <div
      class="flex items-center justify-between px-4 h-[60px] border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <div class="relative flex items-center justify-center size-9 shrink-0">
          <div
            v-if="!shouldShowLoader"
            class="absolute inset-0 rounded-full bg-n-brand/10 ai-glow"
            aria-hidden="true"
          />
          <Icon
            icon="i-woot-captain"
            class="relative z-10 text-n-brand text-2xl"
          />
          <span
            class="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full ring-2 ring-n-solid-1"
            :class="statusDotColor"
            aria-hidden="true"
          />
        </div>
        <div class="flex flex-col min-w-0">
          <span
            class="text-[15px] font-semibold text-n-slate-12 leading-tight truncate"
          >
            {{ $t('CAPTAIN.COPILOT.TITLE') }}
          </span>
          <span class="text-xs text-n-slate-10 leading-tight truncate">
            {{ statusLabel }}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-1 shrink-0">
        <button
          v-for="btn in copilotButtons"
          :key="btn.key"
          v-tooltip="btn.tooltip"
          class="flex items-center justify-center size-8 rounded-lg hover:bg-n-slate-3 transition-colors"
          @click="handleSidebarAction(btn.key)"
        >
          <span :class="btn.icon" class="size-4 text-n-slate-11" />
        </button>
        <button
          class="flex items-center justify-center size-8 rounded-lg hover:bg-n-slate-3 transition-colors"
          @click="closeCopilotPanel"
        >
          <span class="i-lucide-x size-4 text-n-slate-11" />
        </button>
      </div>
    </div>
    <div
      ref="chatContainer"
      class="flex-1 flex px-4 py-4 overflow-y-auto items-start bg-n-slate-2/50 dark:bg-n-solid-2"
    >
      <div v-if="hasMessages" class="space-y-4 flex-1 flex flex-col w-full">
        <template v-for="(item, index) in groupedMessages" :key="item.id">
          <CopilotAgentMessage
            v-if="item.message_type === 'user'"
            :message="item.message"
          />
          <CopilotAssistantMessage
            v-else-if="item.message_type === 'assistant'"
            :message="item.message"
            :is-last-message="index === groupedMessages.length - 1"
            :conversation-inbox-type="conversationInboxType"
          />
          <CopilotThinkingGroup
            v-else
            :messages="item.messages"
            :default-collapsed="isLastMessageFromAssistant"
          />
        </template>
        <div
          v-if="hasTimedOut"
          class="rounded-lg border border-n-weak bg-n-alpha-2 p-3 flex flex-col gap-2"
        >
          <p class="text-sm font-medium text-n-slate-12">
            {{ $t('CAPTAIN.COPILOT.RESPONSE_TIMEOUT_TITLE') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ timeoutMessage || $t('CAPTAIN.COPILOT.RESPONSE_TIMEOUT_BODY') }}
          </p>
          <div>
            <Button
              :label="$t('CAPTAIN.COPILOT.RETRY')"
              sm
              slate
              @click="$emit('retry')"
            />
          </div>
        </div>
        <CopilotLoader v-else-if="shouldShowLoader" />
      </div>
      <CopilotEmptyState
        v-else
        :has-assistants="hasAssistants"
        @use-suggestion="sendMessage"
      />
    </div>

    <div class="px-4 py-3 border-t border-n-weak">
      <div class="flex items-center gap-2 justify-between w-full mb-1">
        <ToggleCopilotAssistant
          v-if="assistants.length > 1"
          :assistants="assistants"
          :active-assistant="activeAssistant"
          @set-assistant="$event => emit('setAssistant', $event)"
        />
        <div v-else />
      </div>
      <CopilotQuickActions v-if="hasAssistants && !hasMessages" @send="sendMessage" />
      <CopilotInput v-if="hasAssistants" class="w-full" @send="sendMessage" />
    </div>
  </div>
</template>
