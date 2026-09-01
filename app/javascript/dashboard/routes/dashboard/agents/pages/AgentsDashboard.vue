<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptainAssistantModel } from 'dashboard/composables/useCaptainAssistantModel';

import AiStatCard from 'dashboard/components-next/agents-ui/AiStatCard.vue';
import AiAgentCard from 'dashboard/components-next/agents-ui/AiAgentCard.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiModal from 'dashboard/components-next/agents-ui/AiModal.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiTextarea from 'dashboard/components-next/agents-ui/AiTextarea.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const { assistantModel } = useCaptainAssistantModel();

const showCreateModal = ref(route.query.create === 'true');
const newAgentName = ref('');
const newAgentDescription = ref('');
const isCreating = ref(false);

const agents = computed(
  () => store.getters['captainAssistants/getRecords'] || []
);
const totalAgents = computed(() => agents.value.length);
// `account_inbox_ids` NÃO existe no payload do assistant: o campo certo é `inbox_ids`
// (ver `_assistant.json.jbuilder`). Lendo o nome errado, o cartão "Caixas Conectadas"
// somava `undefined?.length || 0` e mostrava 0 mesmo com agentes atendendo caixas.
const totalInboxes = computed(() =>
  agents.value.reduce((sum, agent) => sum + (agent.inbox_ids?.length || 0), 0)
);

function navigateToAgent(agent) {
  router.push({
    name: 'agents_assistant_overview',
    params: { accountId: accountId.value, assistantId: agent.id },
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
    if (agent?.id) navigateToAgent(agent);
  } catch {
    useAlert(t('AGENTS_DASHBOARD.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
}
</script>

<template>
  <div class="px-6 pt-5 pb-10 mx-auto max-w-5xl">
    <!-- Header -->
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-[22px] font-extrabold tracking-tight text-n-slate-12">
        {{ t('AGENTS_DASHBOARD.TITLE') }}
      </h1>
      <div class="flex gap-2">
        <AiButton variant="ghost" @click="goToTools">
          <span class="i-lucide-wrench size-4" />
          {{ t('AGENTS_DASHBOARD.TOOLS') }}
        </AiButton>
        <AiButton variant="ghost" @click="goToConnection">
          <span class="i-lucide-plug-zap size-4" />
          {{ t('AGENTS_DASHBOARD.CONNECTION') }}
        </AiButton>
        <AiButton @click="openCreateModal">
          <span class="i-lucide-plus size-4" />
          {{ t('AGENTS_DASHBOARD.NEW_AGENT') }}
        </AiButton>
      </div>
    </div>

    <!-- Stats (count-up) -->
    <div class="grid grid-cols-2 gap-3 mb-6">
      <AiStatCard
        :value="totalAgents"
        :label="t('AGENTS_DASHBOARD.TOTAL_AGENTS')"
        icon="i-lucide-bot"
        tint="#1faa59"
      />
      <AiStatCard
        :value="totalInboxes"
        :label="t('AGENTS_DASHBOARD.TOTAL_INBOXES')"
        icon="i-lucide-inbox"
        tint="#0a84ff"
      />
    </div>

    <!-- Empty -->
    <AiEmptyState
      v-if="agents.length === 0"
      icon="i-lucide-bot"
      :title="t('AGENTS_DASHBOARD.EMPTY_TITLE')"
      :description="t('AGENTS_DASHBOARD.EMPTY_DESCRIPTION')"
    >
      <template #action>
        <AiButton @click="openCreateModal">
          {{ t('AGENTS_DASHBOARD.CREATE_FIRST') }}
        </AiButton>
      </template>
    </AiEmptyState>

    <!-- Grid (cascata) -->
    <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
      <AiAgentCard
        v-for="(agent, i) in agents"
        :key="agent.id"
        :agent="agent"
        :model="assistantModel || ''"
        :inbox-label="t('AGENTS_DASHBOARD.INBOXES_LABEL')"
        :in-use-label="t('AGENTS_PAGE.IN_USE')"
        :no-inbox-label="t('AGENTS_PAGE.NO_INBOX')"
        :style="{ animationDelay: `${i * 55}ms` }"
        @select="navigateToAgent"
      />
    </div>

    <!-- Criar IA -->
    <AiModal
      v-model="showCreateModal"
      :title="t('AGENTS_DASHBOARD.CREATE_TITLE')"
    >
      <div class="flex flex-col gap-4">
        <div>
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_DASHBOARD.NAME_LABEL') }}
          </label>
          <AiField
            v-model="newAgentName"
            :placeholder="t('AGENTS_DASHBOARD.NAME_PLACEHOLDER')"
          />
        </div>
        <div>
          <label class="block mb-1.5 text-[13px] font-semibold text-n-slate-12">
            {{ t('AGENTS_DASHBOARD.DESCRIPTION_LABEL') }}
          </label>
          <AiTextarea
            v-model="newAgentDescription"
            :rows="3"
            :placeholder="t('AGENTS_DASHBOARD.DESCRIPTION_PLACEHOLDER')"
          />
        </div>
      </div>
      <template #footer>
        <AiButton variant="ghost" @click="closeCreateModal">
          {{ t('AGENTS_DASHBOARD.CANCEL') }}
        </AiButton>
        <AiButton
          :disabled="!newAgentName.trim() || isCreating"
          @click="handleCreate"
        >
          {{
            isCreating
              ? t('AGENTS_DASHBOARD.CREATING')
              : t('AGENTS_DASHBOARD.CREATE')
          }}
        </AiButton>
      </template>
    </AiModal>
  </div>
</template>
