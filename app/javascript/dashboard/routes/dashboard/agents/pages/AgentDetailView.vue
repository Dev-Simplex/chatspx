<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptainAssistantModel } from 'dashboard/composables/useCaptainAssistantModel';

import AiAvatar from 'dashboard/components-next/agents-ui/AiAvatar.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
// O modelo é da CONTA, não do agente: `agent.config.model` nunca existiu no payload
// e o selo simplesmente não aparecia. Ver useCaptainAssistantModel.
const { assistantModel } = useCaptainAssistantModel();

const assistantId = computed(() => Number(route.params.assistantId));

const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const tabs = computed(() => [
  {
    name: 'agents_assistant_overview',
    label: t('AGENT_DETAIL.TABS.OVERVIEW'),
    icon: 'i-lucide-home',
  },
  {
    name: 'agents_assistant_flow',
    label: t('AGENT_DETAIL.TABS.FLOW'),
    icon: 'i-lucide-workflow',
  },
  {
    name: 'agents_assistant_behavior',
    label: t('AGENT_DETAIL.TABS.BEHAVIOR'),
    icon: 'i-lucide-sliders-horizontal',
  },
  {
    name: 'agents_assistant_knowledge',
    label: t('AGENT_DETAIL.TABS.KNOWLEDGE'),
    icon: 'i-lucide-book-open',
  },
  {
    name: 'agents_assistant_scenarios',
    label: t('AGENT_DETAIL.TABS.SCENARIOS'),
    icon: 'i-lucide-git-branch',
  },
  {
    name: 'agents_assistant_inboxes',
    label: t('AGENT_DETAIL.TABS.INBOXES'),
    icon: 'i-lucide-inbox',
  },
  {
    name: 'agents_assistant_logs',
    label: t('AGENT_DETAIL.TABS.LOGS'),
    icon: 'i-lucide-activity',
  },
  {
    name: 'agents_assistant_settings',
    label: t('AGENT_DETAIL.TABS.SETTINGS'),
    icon: 'i-lucide-settings',
  },
]);

function navigateToTab(tab) {
  router.push({
    name: tab.name,
    params: { accountId: accountId.value, assistantId: assistantId.value },
  });
}

function isActiveTab(tab) {
  return route.name === tab.name;
}
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Header -->
    <div
      class="px-6 pt-4 border-b backdrop-blur-xl bg-n-background/80 border-n-weak"
    >
      <div class="flex justify-between items-center mb-3">
        <div class="flex gap-3 items-center">
          <AiAvatar :name="agent?.name || '?'" :size="40" />
          <div>
            <h1 class="text-base font-bold text-n-slate-12">
              {{ agent?.name || t('AGENT_DETAIL.LOADING') }}
            </h1>
            <p v-if="agent?.description" class="text-xs text-n-slate-10">
              {{ agent.description }}
            </p>
          </div>
        </div>
        <span
          v-if="assistantModel"
          class="px-2 py-0.5 font-mono text-xs rounded-md bg-n-alpha-2 text-n-slate-10"
          :title="t('AGENT_DETAIL.ACCOUNT_MODEL')"
        >
          {{ assistantModel }}
        </span>
      </div>

      <!-- Tabs -->
      <nav class="flex overflow-x-auto no-scrollbar">
        <button
          v-for="tab in tabs"
          :key="tab.name"
          type="button"
          class="inline-flex relative gap-1.5 items-center px-3 py-2.5 text-[13px] font-medium whitespace-nowrap transition-colors duration-150"
          :class="
            isActiveTab(tab)
              ? 'font-semibold text-n-brand'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="navigateToTab(tab)"
        >
          <span :class="tab.icon" class="size-4" />
          {{ tab.label }}
          <span
            v-if="isActiveTab(tab)"
            class="absolute inset-x-2 bottom-0 h-0.5 rounded-full bg-n-brand"
          />
        </button>
      </nav>
    </div>

    <!-- Content -->
    <div class="overflow-y-auto flex-1 bg-n-background">
      <router-view />
    </div>
  </div>
</template>
