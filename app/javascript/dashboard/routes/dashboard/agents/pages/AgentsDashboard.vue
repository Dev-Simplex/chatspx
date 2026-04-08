<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();

const showCreateModal = ref(route.query.create === 'true');
const newAgentName = ref('');
const newAgentDescription = ref('');
const isCreating = ref(false);

const agents = computed(
  () => store.getters['captainAssistants/getRecords'] || []
);

const totalAgents = computed(() => agents.value.length);
const totalInboxes = computed(() =>
  agents.value.reduce(
    (sum, agent) => sum + (agent.account_inbox_ids?.length || 0),
    0
  )
);

function navigateToAgent(agent) {
  router.push({
    name: 'agents_assistant_overview',
    params: { accountId: accountId.value, assistantId: agent.id },
  });
}

function openCreateModal() {
  showCreateModal.value = true;
}

function closeCreateModal() {
  showCreateModal.value = false;
  newAgentName.value = '';
  newAgentDescription.value = '';
}

async function handleCreate() {
  if (!newAgentName.value.trim()) return;
  isCreating.value = true;
  try {
    const agent = await store.dispatch('captainAssistants/create', {
      name: newAgentName.value.trim(),
      description: newAgentDescription.value.trim(),
    });
    useAlert(t('AGENTS_DASHBOARD.CREATE_SUCCESS'));
    closeCreateModal();
    if (agent?.id) {
      navigateToAgent(agent);
    }
  } catch {
    useAlert(t('AGENTS_DASHBOARD.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
}
</script>

<template>
  <div class="p-6">
    <!-- Header -->
    <div class="mb-6 flex items-center justify-between">
      <h1 class="text-lg font-semibold text-n-slate-12">
        {{ t('AGENTS_DASHBOARD.TITLE') }}
      </h1>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
        @click="openCreateModal"
      >
        <i class="i-lucide-plus size-4" />
        {{ t('AGENTS_DASHBOARD.NEW_AGENT') }}
      </button>
    </div>

    <!-- Stats -->
    <div class="mb-6 flex gap-4">
      <div
        class="flex items-center gap-3 rounded-xl border border-n-weak bg-white p-4 dark:bg-n-solid-2"
      >
        <div
          class="flex size-10 items-center justify-center rounded-lg bg-primary-50 dark:bg-primary-900/20"
        >
          <i class="i-lucide-bot size-5 text-primary-500" />
        </div>
        <div>
          <p class="text-2xl font-bold tabular-nums text-n-slate-12">
            {{ totalAgents }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('AGENTS_DASHBOARD.TOTAL_AGENTS') }}
          </p>
        </div>
      </div>
      <div
        class="flex items-center gap-3 rounded-xl border border-n-weak bg-white p-4 dark:bg-n-solid-2"
      >
        <div
          class="flex size-10 items-center justify-center rounded-lg bg-primary-50 dark:bg-primary-900/20"
        >
          <i class="i-lucide-inbox size-5 text-primary-500" />
        </div>
        <div>
          <p class="text-2xl font-bold tabular-nums text-n-slate-12">
            {{ totalInboxes }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('AGENTS_DASHBOARD.TOTAL_INBOXES') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div
      v-if="agents.length === 0"
      class="flex flex-col items-center justify-center rounded-xl border border-dashed border-n-weak py-16"
    >
      <i class="i-lucide-bot mb-4 size-12 text-n-slate-9 opacity-20" />
      <p class="mb-2 text-base font-medium text-n-slate-12">
        {{ t('AGENTS_DASHBOARD.EMPTY_TITLE') }}
      </p>
      <p class="mb-6 text-sm text-n-slate-10">
        {{ t('AGENTS_DASHBOARD.EMPTY_DESCRIPTION') }}
      </p>
      <button
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
        @click="openCreateModal"
      >
        {{ t('AGENTS_DASHBOARD.CREATE_FIRST') }}
      </button>
    </div>

    <!-- Agent Cards Grid -->
    <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
      <button
        v-for="agent in agents"
        :key="agent.id"
        type="button"
        class="group flex flex-col rounded-xl border border-n-weak bg-white p-5 text-left transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
        @click="navigateToAgent(agent)"
      >
        <div class="mb-3 flex items-center gap-3">
          <div
            class="flex size-10 items-center justify-center rounded-lg bg-gradient-to-br from-primary-500 to-blue-500 text-base font-semibold text-white"
          >
            {{ (agent.name || '?')[0].toUpperCase() }}
          </div>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-n-slate-12">
              {{ agent.name }}
            </p>
            <p v-if="agent.config?.llm_model" class="text-xs text-n-slate-10">
              {{ agent.config.llm_model }}
            </p>
          </div>
        </div>
        <p
          v-if="agent.description"
          class="mb-3 line-clamp-2 text-sm text-n-slate-10"
        >
          {{ agent.description }}
        </p>
        <div
          class="mt-auto flex items-center justify-between border-t border-n-weak pt-3 text-xs text-n-slate-10"
        >
          <span class="flex items-center gap-1">
            <i class="i-lucide-inbox size-3" />
            {{ agent.account_inbox_ids?.length || 0 }}
            {{ t('AGENTS_DASHBOARD.INBOXES_LABEL') }}
          </span>
          <span class="inline-flex items-center gap-1.5">
            <span
              class="size-1.5 rounded-full"
              :class="agent.active ? 'bg-green-500' : 'bg-n-slate-8'"
            />
            {{
              agent.active ? t('AGENTS_PAGE.ACTIVE') : t('AGENTS_PAGE.INACTIVE')
            }}
          </span>
        </div>
      </button>
    </div>

    <!-- Create Modal -->
    <Teleport to="body">
      <div
        v-if="showCreateModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-5"
        @click.self="closeCreateModal"
      >
        <div class="w-full max-w-md rounded-2xl bg-n-solid-1 p-6 shadow-xl">
          <h3 class="mb-4 text-lg font-semibold text-n-slate-12">
            {{ t('AGENTS_DASHBOARD.CREATE_TITLE') }}
          </h3>
          <div class="flex flex-col gap-4">
            <div>
              <label class="mb-1 block text-sm font-medium text-n-slate-12">
                {{ t('AGENTS_DASHBOARD.NAME_LABEL') }}
              </label>
              <input
                v-model="newAgentName"
                type="text"
                class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                :placeholder="t('AGENTS_DASHBOARD.NAME_PLACEHOLDER')"
              />
            </div>
            <div>
              <label class="mb-1 block text-sm font-medium text-n-slate-12">
                {{ t('AGENTS_DASHBOARD.DESCRIPTION_LABEL') }}
              </label>
              <textarea
                v-model="newAgentDescription"
                rows="3"
                class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                :placeholder="t('AGENTS_DASHBOARD.DESCRIPTION_PLACEHOLDER')"
              />
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              class="rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-2"
              @click="closeCreateModal"
            >
              {{ t('AGENTS_DASHBOARD.CANCEL') }}
            </button>
            <button
              type="button"
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white transition hover:brightness-95 disabled:opacity-60"
              :disabled="!newAgentName.trim() || isCreating"
              @click="handleCreate"
            >
              {{
                isCreating
                  ? t('AGENTS_DASHBOARD.CREATING')
                  : t('AGENTS_DASHBOARD.CREATE')
              }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
