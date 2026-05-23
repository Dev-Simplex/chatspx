<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

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

onMounted(() => {
  store.dispatch('captainAssistants/get');
});
</script>

<template>
  <div class="flex h-full w-full">
    <!-- Sidebar -->
    <div
      class="flex w-64 shrink-0 flex-col border-r border-n-weak bg-white dark:bg-n-solid-1"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between border-b border-n-weak px-4 py-3"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('AGENTS_PAGE.TITLE') }}
        </h2>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-lg bg-n-brand px-2.5 py-1.5 text-xs font-medium text-white transition-colors hover:brightness-95"
          @click="navigateToCreate"
        >
          <i class="i-lucide-plus size-3" />
          {{ t('AGENTS_PAGE.NEW') }}
        </button>
      </div>

      <!-- Search -->
      <div class="px-3 py-2">
        <div class="relative">
          <i
            class="i-lucide-search absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-n-slate-9"
          />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('AGENTS_PAGE.SEARCH_PLACEHOLDER')"
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 py-1.5 pl-8 pr-3 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
          />
        </div>
      </div>

      <!-- Agent List -->
      <div class="flex-1 overflow-y-auto px-2 py-1">
        <div
          v-if="isFetching"
          class="px-3 py-8 text-center text-sm text-n-slate-10"
        >
          {{ t('AGENTS_PAGE.LOADING') }}
        </div>
        <div
          v-else-if="filteredAgents.length === 0"
          class="px-3 py-8 text-center text-sm text-n-slate-10"
        >
          {{ t('AGENTS_PAGE.NO_AGENTS') }}
        </div>
        <template v-else>
          <button
            v-for="agent in filteredAgents"
            :key="agent.id"
            type="button"
            class="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left transition-colors duration-150"
            :class="
              selectedAssistantId === agent.id
                ? 'bg-n-alpha-2 font-medium'
                : 'hover:bg-n-alpha-1'
            "
            @click="navigateToAgent(agent)"
          >
            <div
              class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary-500 to-blue-500 text-xs font-semibold text-white"
            >
              {{ (agent.name || '?')[0].toUpperCase() }}
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm text-n-slate-12">
                {{ agent.name }}
              </p>
            </div>
            <span
              class="inline-flex items-center gap-1 text-xs text-n-slate-10"
            >
              <span
                class="size-1.5 shrink-0 rounded-full"
                :class="agent.active ? 'bg-green-500' : 'bg-n-slate-8'"
              />
            </span>
          </button>
        </template>
      </div>
    </div>

    <!-- Main Content -->
    <div class="flex-1 overflow-y-auto bg-n-background">
      <router-view />
    </div>
  </div>
</template>
