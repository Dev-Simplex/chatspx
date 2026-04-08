<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import LottieIcon from 'dashboard/components-next/agents/LottieIcon.vue';
import homeAnim from 'dashboard/assets/lottie/useanimations/home.json';
import settingsAnim from 'dashboard/assets/lottie/useanimations/settings.json';
import bookmarkAnim from 'dashboard/assets/lottie/useanimations/bookmark.json';
import settings2Anim from 'dashboard/assets/lottie/useanimations/settings2.json';
import exploreAnim from 'dashboard/assets/lottie/useanimations/explore.json';
import downloadAnim from 'dashboard/assets/lottie/useanimations/download.json';
import activityAnim from 'dashboard/assets/lottie/useanimations/activity.json';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();

const assistantId = computed(() => Number(route.params.assistantId));

const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const tabs = computed(() => [
  {
    name: 'agents_assistant_overview',
    label: t('AGENT_DETAIL.TABS.OVERVIEW'),
    animation: homeAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_behavior',
    label: t('AGENT_DETAIL.TABS.BEHAVIOR'),
    animation: settingsAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_knowledge',
    label: t('AGENT_DETAIL.TABS.KNOWLEDGE'),
    animation: bookmarkAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_tools',
    label: t('AGENT_DETAIL.TABS.TOOLS'),
    animation: settings2Anim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_scenarios',
    label: t('AGENT_DETAIL.TABS.SCENARIOS'),
    animation: exploreAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_inboxes',
    label: t('AGENT_DETAIL.TABS.INBOXES'),
    animation: downloadAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_logs',
    label: t('AGENT_DETAIL.TABS.LOGS'),
    animation: activityAnim,
    mode: 'hover',
  },
  {
    name: 'agents_assistant_settings',
    label: t('AGENT_DETAIL.TABS.SETTINGS'),
    animation: settingsAnim,
    mode: 'hover',
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
  <div class="flex h-full flex-col">
    <!-- Header -->
    <div class="border-b border-n-weak bg-white px-6 py-4 dark:bg-n-solid-1">
      <div class="mb-3 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div
            class="flex size-10 items-center justify-center rounded-lg bg-gradient-to-br from-primary-500 to-blue-500 text-base font-semibold text-white shadow-sm"
          >
            {{ (agent?.name || '?')[0].toUpperCase() }}
          </div>
          <div>
            <h1 class="text-base font-semibold text-n-slate-12">
              {{ agent?.name || t('AGENT_DETAIL.LOADING') }}
            </h1>
            <p v-if="agent?.description" class="text-xs text-n-slate-10">
              {{ agent.description }}
            </p>
          </div>
        </div>
        <span
          v-if="agent?.config?.model"
          class="rounded-md bg-n-alpha-2 px-2 py-0.5 font-mono text-xs text-n-slate-10"
        >
          {{ agent.config.model }}
        </span>
      </div>

      <!-- Tab Navigation -->
      <nav class="flex">
        <button
          v-for="tab in tabs"
          :key="tab.name"
          type="button"
          class="relative inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors duration-150"
          :class="
            isActiveTab(tab)
              ? 'font-semibold text-n-brand'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="navigateToTab(tab)"
        >
          <LottieIcon
            :animation-data="tab.animation"
            :size="14"
            :mode="tab.mode"
          />
          {{ tab.label }}
          <span
            v-if="isActiveTab(tab)"
            class="absolute inset-x-0 bottom-0 h-0.5 rounded-full bg-n-brand"
          />
        </button>
      </nav>
    </div>

    <!-- Tab Content -->
    <div class="flex-1 overflow-y-auto">
      <router-view />
    </div>
  </div>
</template>
