<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

import AiSearch from 'dashboard/components-next/agents-ui/AiSearch.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiAvatar from 'dashboard/components-next/agents-ui/AiAvatar.vue';
import AiBackdrop from 'dashboard/components-next/agents-ui/AiBackdrop.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();

const searchQuery = ref('');

const agents = computed(
  () => store.getters['captainAssistants/getRecords'] || []
);
const isFetching = computed(
  () => store.getters['captainAssistants/getUIFlags']?.isFetching || false
);
const filteredAgents = computed(() => {
  if (!searchQuery.value) return agents.value;
  const q = searchQuery.value.toLowerCase();
  return agents.value.filter(a => a.name?.toLowerCase().includes(q));
});
const selectedAssistantId = computed(() => {
  const id = route.params.assistantId;
  return id ? Number(id) : null;
});

function navigateToAgent(agent) {
  router.push({
    name: 'agents_assistant_overview',
    params: { accountId: accountId.value, assistantId: agent.id },
  });
}
function navigateToCreate() {
  router.push({
    name: 'agents_dashboard',
    params: { accountId: accountId.value },
    query: { create: true },
  });
}
function goToConnection() {
  router.push({
    name: 'agents_settings',
    params: { accountId: accountId.value },
  });
}
function goToTools() {
  router.push({
    name: 'agents_tools',
    params: { accountId: accountId.value },
  });
}
function goToEvaluation() {
  router.push({
    name: 'agents_evaluation',
    params: { accountId: accountId.value },
  });
}
const connectionActive = computed(() => route.name === 'agents_settings');
const toolsActive = computed(() => route.name === 'agents_tools');
const evaluationActive = computed(() => route.name === 'agents_evaluation');
onMounted(() => store.dispatch('captainAssistants/get'));
</script>

<template>
  <div class="flex w-full h-full">
    <!-- Sidebar -->
    <div
      class="flex flex-col w-64 border-r shrink-0 border-n-weak bg-n-solid-1"
    >
      <div
        class="flex justify-between items-center px-4 py-3 border-b border-n-weak"
      >
        <h2 class="text-[15px] font-bold tracking-tight text-n-slate-12">
          {{ t('AGENTS_PAGE.TITLE') }}
        </h2>
        <AiButton variant="subtle" @click="navigateToCreate">
          <span class="i-lucide-plus size-3.5" />
          {{ t('AGENTS_PAGE.NEW') }}
        </AiButton>
      </div>

      <div class="px-3 py-2.5">
        <AiSearch
          v-model="searchQuery"
          :placeholder="t('AGENTS_PAGE.SEARCH_PLACEHOLDER')"
        />
      </div>

      <div class="overflow-y-auto flex-1 px-2 py-1 space-y-0.5">
        <div
          v-if="isFetching"
          class="px-3 py-8 text-sm text-center text-n-slate-10"
        >
          {{ t('AGENTS_PAGE.LOADING') }}
        </div>
        <div
          v-else-if="filteredAgents.length === 0"
          class="px-3 py-8 text-sm text-center text-n-slate-10"
        >
          {{ t('AGENTS_PAGE.NO_AGENTS') }}
        </div>
        <template v-else>
          <button
            v-for="agent in filteredAgents"
            :key="agent.id"
            type="button"
            class="flex gap-3 items-center px-2.5 py-2 w-full text-left rounded-xl transition-colors duration-150"
            :class="
              selectedAssistantId === agent.id
                ? 'bg-n-alpha-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="navigateToAgent(agent)"
          >
            <AiAvatar :name="agent.name" :size="30" />
            <span
              class="flex-1 text-[13.5px] truncate text-n-slate-12"
              :class="selectedAssistantId === agent.id ? 'font-bold' : ''"
            >
              {{ agent.name }}
            </span>
            <span
              class="flex-none rounded-full size-2"
              :class="agent.active === false ? 'bg-n-slate-7' : 'bg-g-500'"
            />
          </button>
        </template>
      </div>

      <!-- Avaliação / Ferramentas / Conexão -->
      <div class="p-2 space-y-0.5 border-t border-n-weak">
        <button
          type="button"
          class="flex gap-2.5 items-center px-2.5 py-2 w-full text-left rounded-xl transition-colors"
          :class="evaluationActive ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
          @click="goToEvaluation"
        >
          <span
            class="grid flex-none place-items-center text-white rounded-lg bg-n-brand size-7"
          >
            <span class="i-lucide-gauge size-4" />
          </span>
          <span
            class="text-[13px] font-semibold text-n-slate-12"
            :class="evaluationActive ? 'font-bold' : ''"
          >
            {{ t('AGENTS_EVALUATION.TITLE') }}
          </span>
        </button>
        <button
          type="button"
          class="flex gap-2.5 items-center px-2.5 py-2 w-full text-left rounded-xl transition-colors"
          :class="toolsActive ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
          @click="goToTools"
        >
          <span
            class="grid flex-none place-items-center text-white rounded-lg bg-n-brand size-7"
          >
            <span class="i-lucide-wrench size-4" />
          </span>
          <span
            class="text-[13px] font-semibold text-n-slate-12"
            :class="toolsActive ? 'font-bold' : ''"
          >
            {{ t('AGENTS_PAGE.TOOLS') }}
          </span>
        </button>
        <button
          type="button"
          class="flex gap-2.5 items-center px-2.5 py-2 w-full text-left rounded-xl transition-colors"
          :class="connectionActive ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
          @click="goToConnection"
        >
          <span
            class="grid flex-none place-items-center text-white rounded-lg bg-n-brand size-7"
          >
            <span class="i-lucide-plug-zap size-4" />
          </span>
          <span
            class="text-[13px] font-semibold text-n-slate-12"
            :class="connectionActive ? 'font-bold' : ''"
          >
            {{ t('AGENTS_DASHBOARD.CONNECTION') }}
          </span>
        </button>
      </div>
    </div>

    <!-- Conteúdo -->
    <div class="overflow-y-auto isolate relative flex-1 bg-n-background">
      <AiBackdrop />
      <div class="relative">
        <router-view />
      </div>
    </div>
  </div>
</template>
