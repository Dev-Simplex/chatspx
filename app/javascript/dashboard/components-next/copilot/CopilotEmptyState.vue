<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from '../icon/Icon.vue';

defineProps({
  hasAssistants: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const routePromptMap = {
  conversations: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
      icon: 'i-lucide-list',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.CONTENT',
      icon: 'i-lucide-sparkles',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.RATE.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.RATE.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.RATE.CONTENT',
      icon: 'i-lucide-star',
    },
  ],
  dashboard: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT',
      icon: 'i-lucide-flag',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT',
      icon: 'i-lucide-users',
    },
  ],
};

const getCurrentRoute = () => {
  const path = route.path;
  if (path.includes('/conversations')) return 'conversations';
  if (path.includes('/dashboard')) return 'dashboard';
  return 'dashboard';
};

const promptOptions = computed(() => {
  const currentRoute = getCurrentRoute();
  return routePromptMap[currentRoute] || routePromptMap.conversations;
});

const handleSuggestion = opt => {
  emit('useSuggestion', t(opt.prompt));
};
</script>

<template>
  <div
    class="flex-1 flex flex-col items-center justify-center gap-6 px-2 py-8 w-full"
  >
    <div class="flex flex-col items-center text-center space-y-3">
      <div class="relative flex items-center justify-center size-16">
        <div
          class="absolute inset-0 rounded-full ai-glow bg-n-brand/10"
          aria-hidden="true"
        />
        <Icon
          icon="i-woot-captain"
          class="text-n-brand text-5xl relative z-10"
        />
      </div>
      <div class="space-y-1.5 max-w-[260px]">
        <h3 class="text-base font-semibold text-n-slate-12 leading-7">
          {{ $t('CAPTAIN.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-snug">
          {{ $t('CAPTAIN.COPILOT.KICK_OFF_MESSAGE') }}
        </p>
      </div>
    </div>

    <div v-if="!hasAssistants" class="w-full space-y-2 text-center">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'agents_dashboard',
          params: { accountId: route.params.accountId },
        }"
        class="text-sm text-n-brand hover:underline"
      >
        {{ $t('CAPTAIN.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>

    <div v-else class="w-full space-y-2.5">
      <span
        class="text-xs font-semibold text-n-slate-10 uppercase tracking-wider block px-1"
      >
        {{ $t('CAPTAIN.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="flex flex-col gap-2">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="group flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-left transition-all duration-200 hover:border-n-brand/40 hover:bg-n-brand/5 hover:-translate-y-0.5 hover:shadow-sm motion-reduce:hover:translate-y-0"
          @click="handleSuggestion(prompt)"
        >
          <span
            :class="prompt.icon"
            class="size-4 mt-0.5 shrink-0 text-n-brand"
          />
          <div class="flex flex-col gap-0.5 min-w-0">
            <span class="text-sm font-medium text-n-slate-12 leading-tight">
              {{ t(prompt.label) }}
            </span>
            <span class="text-xs text-n-slate-10 leading-snug">
              {{ t(prompt.description) }}
            </span>
          </div>
        </button>
      </div>
    </div>
  </div>
</template>
