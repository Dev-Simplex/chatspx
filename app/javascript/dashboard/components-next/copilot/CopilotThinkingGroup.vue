<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '../icon/Icon.vue';
import CopilotThinkingBlock from './CopilotThinkingBlock.vue';

const props = defineProps({
  messages: { type: Array, required: true },
  defaultCollapsed: { type: Boolean, default: false },
});
const { t, locale } = useI18n();
const isExpanded = ref(!props.defaultCollapsed);

const thinkingCount = computed(() => props.messages.length);
const currentLocale = computed(() =>
  String(locale?.value || '')
    .toLowerCase()
    .replace('-', '_')
);
const isPtBrLocale = computed(() => currentLocale.value === 'pt_br');

const TOOL_LABELS = {
  get_conversation: 'GET_CONVERSATION',
  search_conversation: 'SEARCH_CONVERSATION',
  search_contacts: 'SEARCH_CONTACTS',
  get_contact: 'GET_CONTACT',
  search_articles: 'SEARCH_ARTICLES',
  get_article: 'GET_ARTICLE',
  search_documentation: 'SEARCH_DOCUMENTATION',
  search_linear_issues: 'SEARCH_LINEAR_ISSUES',
};

const parseLegacyToolEvent = content => {
  if (content?.startsWith('Using ')) {
    return 'started';
  }

  if (content?.startsWith('Completed ')) {
    return 'completed';
  }

  return null;
};

const parseLegacyFunctionName = (content, toolEvent) => {
  const prefix = toolEvent === 'completed' ? 'Completed ' : 'Using ';
  if (!content?.startsWith(prefix)) {
    return '';
  }

  return content.slice(prefix.length).trim();
};

const resolveToolLabel = functionName => {
  const normalizedName = String(functionName || '')
    .trim()
    .toLowerCase();
  const translationKey = TOOL_LABELS[normalizedName] || 'FALLBACK';

  return t(`CAPTAIN.COPILOT.THINKING.TOOLS.${translationKey}`);
};

const formatThinkingContent = copilotMessage => {
  const messagePayload = copilotMessage?.message || {};
  const rawContent = messagePayload.content || '';

  if (!isPtBrLocale.value) {
    return rawContent;
  }

  const toolEvent =
    messagePayload.tool_event || parseLegacyToolEvent(rawContent);
  if (!toolEvent) {
    return rawContent;
  }

  const functionName =
    messagePayload.function_name ||
    parseLegacyFunctionName(rawContent, toolEvent);
  const target = resolveToolLabel(functionName);

  if (toolEvent === 'started') {
    return t('CAPTAIN.COPILOT.THINKING.STARTED', { target });
  }

  if (toolEvent === 'completed') {
    return t('CAPTAIN.COPILOT.THINKING.COMPLETED', { target });
  }

  return rawContent;
};

watch(
  () => props.defaultCollapsed,
  newValue => {
    if (newValue) {
      isExpanded.value = false;
    }
  }
);
</script>

<template>
  <div class="border border-n-weak/50 rounded-lg overflow-hidden">
    <button
      class="w-full px-3 py-2 flex items-center gap-2 cursor-pointer hover:bg-n-slate-3/30 text-xs text-n-slate-10 transition-colors duration-200"
      @click="isExpanded = !isExpanded"
    >
      <Icon
        icon="i-lucide-sparkles"
        class="w-3.5 h-3.5 flex-shrink-0 animate-pulse"
      />
      <span class="flex items-center gap-2 flex-1">
        {{ t('CAPTAIN.COPILOT.SHOW_STEPS') }}
        <span
          class="inline-flex items-center justify-center h-4 min-w-4 px-1 text-xs font-medium rounded-full bg-n-solid-3 text-n-slate-11"
        >
          {{ thinkingCount }}
        </span>
      </span>
      <Icon
        :icon="isExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        class="w-3.5 h-3.5 transition-transform duration-200"
      />
    </button>
    <div
      v-show="isExpanded"
      class="px-3 py-2 bg-n-slate-2/50 border-t border-n-weak/50 space-y-2 transition-all duration-200"
      :class="{
        'opacity-100': isExpanded,
        'opacity-0 max-h-0 overflow-hidden': !isExpanded,
      }"
    >
      <CopilotThinkingBlock
        v-for="copilotMessage in messages"
        :key="copilotMessage.id"
        :content="formatThinkingContent(copilotMessage)"
        :reasoning="copilotMessage.message.reasoning"
      />
    </div>
  </div>
</template>
