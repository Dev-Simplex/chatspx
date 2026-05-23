<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useClipboard } from '@vueuse/core';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const tools = computed(() => store.getters['captainCustomTools/getRecords']);
const isFetching = computed(
  () => store.getters['captainCustomTools/getUIFlags'].isFetching
);

const showForm = ref(false);
const newTool = ref({
  name: '',
  description: '',
  url: '',
  method: 'POST',
  auth_type: 'none',
});

onMounted(() => {
  store.dispatch('captainCustomTools/get', {
    assistantId: assistantId.value,
  });
});

async function createTool() {
  await store.dispatch('captainCustomTools/create', {
    assistantId: assistantId.value,
    ...newTool.value,
  });
  showForm.value = false;
  newTool.value = {
    name: '',
    description: '',
    url: '',
    method: 'POST',
    auth_type: 'none',
  };
}

const COPILOT_TOOLS = [
  {
    name: 'search_documentation',
    description: 'Search knowledge base documents',
  },
  {
    name: 'get_conversation',
    description: 'Get conversation details and messages',
  },
  {
    name: 'search_conversations',
    description: 'Search conversations by query',
  },
  { name: 'get_contact', description: 'Get contact information' },
  { name: 'get_article', description: 'Get help center article content' },
  { name: 'search_articles', description: 'Search help center articles' },
  {
    name: 'search_contacts',
    description: 'Search contacts by name, email or phone',
  },
  { name: 'search_linear_issues', description: 'Search Linear project issues' },
  {
    name: 'get_account_stats',
    description: 'Get account statistics and metrics',
  },
  {
    name: 'get_agent_workload',
    description: 'Get agent workload distribution',
  },
  { name: 'get_team_info', description: 'Get team details and members' },
  {
    name: 'assign_conversation',
    description: 'Assign conversation to an agent',
  },
  { name: 'add_label', description: 'Add label to conversation' },
  { name: 'change_status', description: 'Change conversation status' },
  { name: 'change_priority', description: 'Change conversation priority' },
  { name: 'get_csat_data', description: 'Get CSAT survey results' },
  {
    name: 'search_messages',
    description: 'Search messages across conversations',
  },
  {
    name: 'get_inbox_info',
    description: 'Get inbox details and configuration',
  },
  {
    name: 'get_conversation_full',
    description: 'Get full conversation with all messages',
  },
  { name: 'send_message', description: 'Send message in conversation' },
  { name: 'send_template', description: 'Send WhatsApp template message' },
  { name: 'update_contact', description: 'Update contact information' },
  {
    name: 'set_custom_attributes',
    description: 'Set custom attributes on conversation or contact',
  },
  { name: 'remove_label', description: 'Remove label from conversation' },
  {
    name: 'snooze_conversation',
    description: 'Snooze conversation for N hours',
  },
  {
    name: 'transfer_to_inbox',
    description: 'Transfer conversation to another inbox',
  },
  {
    name: 'get_contact_conversations',
    description: 'Get all conversations of a contact',
  },
  { name: 'add_note_to_contact', description: 'Add note to contact' },
  { name: 'resolve_conversation', description: 'Resolve conversation' },
  { name: 'get_labels', description: 'List all available labels' },
  { name: 'get_agents', description: 'List all agents in the account' },
];

const { copy: copyMcp, copied: copiedMcp } = useClipboard({
  copiedDuring: 2000,
});

const mcpTemplate = JSON.stringify(
  {
    mcpServers: {
      chatspx: {
        command: 'npx',
        args: ['-y', '@anthropic/mcp-server-chatspx'],
        env: {
          CHATSPX_API_URL: 'https://chatspx.app',
          CHATSPX_API_TOKEN: 'your-api-token-here',
        },
      },
    },
  },
  null,
  2
);

function copyMcpTemplate() {
  copyMcp(mcpTemplate);
}
</script>

<template>
  <div class="space-y-6 p-6">
    <!-- Copilot Tools do Sistema -->
    <div
      class="overflow-hidden rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-5 py-3"
      >
        <div class="flex items-center gap-2">
          <i class="i-lucide-sparkles size-4 text-n-brand" />
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.TOOLS.COPILOT_TOOLS') }}
          </h3>
        </div>
        <span
          class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-10"
        >
          {{ COPILOT_TOOLS.length }}
          {{ t('CAPTAIN.AGENT_TABS.TOOLS.AVAILABLE') }}
        </span>
      </div>
      <div class="max-h-80 divide-y divide-n-weak overflow-y-auto">
        <div
          v-for="tool in COPILOT_TOOLS"
          :key="tool.name"
          class="flex cursor-default items-center gap-3 px-5 py-2.5 transition-colors hover:bg-n-alpha-1"
        >
          <i class="i-lucide-wrench size-3.5 shrink-0 text-n-slate-10" />
          <div class="min-w-0 flex-1">
            <p class="font-mono text-sm text-n-slate-12">{{ tool.name }}</p>
            <p class="truncate text-xs text-n-slate-10">
              {{ tool.description }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Custom Tools -->
    <div
      class="overflow-hidden rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-5 py-3"
      >
        <div class="flex items-center gap-2">
          <i class="i-lucide-wrench size-4 text-n-brand" />
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.TOOLS.CUSTOM_TOOLS') }}
          </h3>
        </div>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
          @click="showForm = !showForm"
        >
          <i class="i-lucide-plus size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.TOOLS.NEW_TOOL') }}
        </button>
      </div>
      <div class="p-5">
        <!-- New Tool Form -->
        <div
          v-if="showForm"
          class="mb-4 space-y-3 rounded-xl border border-n-weak bg-n-alpha-1 p-5"
        >
          <div>
            <label class="mb-1.5 block text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.AGENT_TABS.TOOLS.NAME_PLACEHOLDER') }}
            </label>
            <input
              v-model="newTool.name"
              :placeholder="t('CAPTAIN.AGENT_TABS.TOOLS.NAME_PLACEHOLDER')"
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors placeholder:text-n-slate-9 focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
            />
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.AGENT_TABS.TOOLS.DESCRIPTION_PLACEHOLDER') }}
            </label>
            <input
              v-model="newTool.description"
              :placeholder="
                t('CAPTAIN.AGENT_TABS.TOOLS.DESCRIPTION_PLACEHOLDER')
              "
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors placeholder:text-n-slate-9 focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
            />
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-n-slate-12">
              {{ t('CAPTAIN.AGENT_TABS.TOOLS.URL_PLACEHOLDER') }}
            </label>
            <input
              v-model="newTool.url"
              :placeholder="t('CAPTAIN.AGENT_TABS.TOOLS.URL_PLACEHOLDER')"
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors placeholder:text-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
            />
          </div>
          <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <div class="flex gap-3">
            <select
              v-model="newTool.method"
              class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
            >
              <option value="GET">GET</option>
              <option value="POST">POST</option>
              <option value="PUT">PUT</option>
              <option value="DELETE">DELETE</option>
            </select>
            <select
              v-model="newTool.auth_type"
              class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
            >
              <option value="none">Sem Auth</option>
              <option value="api_key">API Key</option>
              <option value="bearer">Bearer Token</option>
            </select>
          </div>
          <!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <div class="flex justify-end">
            <button
              type="button"
              class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
              @click="createTool"
            >
              {{ t('CAPTAIN.AGENT_TABS.TOOLS.SAVE') }}
            </button>
          </div>
        </div>

        <div
          v-if="isFetching"
          class="flex items-center gap-2 text-sm text-n-slate-10"
        >
          <i class="i-lucide-loader-2 size-3.5 animate-spin" />
          {{ t('CAPTAIN.AGENT_TABS.TOOLS.LOADING') }}
        </div>
        <div v-else-if="!tools.length && !showForm" class="py-12 text-center">
          <i class="i-lucide-wrench mx-auto mb-3 size-10 text-n-slate-9" />
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.TOOLS.NO_TOOLS') }}
          </p>
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="tool in tools"
            :key="tool.id"
            class="rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div
                  class="flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
                >
                  <i class="i-lucide-wrench size-4 text-n-slate-11" />
                </div>
                <div>
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ tool.name }}
                  </p>
                  <p
                    v-if="tool.description"
                    class="mt-0.5 text-sm text-n-slate-10"
                  >
                    {{ tool.description }}
                  </p>
                </div>
              </div>
              <span
                class="inline-flex items-center gap-1.5 text-xs"
                :class="
                  tool.enabled !== false
                    ? 'text-green-700 dark:text-green-400'
                    : 'text-n-slate-10'
                "
              >
                <span
                  class="size-1.5 rounded-full"
                  :class="
                    tool.enabled !== false ? 'bg-green-500' : 'bg-n-slate-8'
                  "
                />
                {{
                  tool.enabled !== false
                    ? t('CAPTAIN.AGENT_TABS.TOOLS.ACTIVE')
                    : t('CAPTAIN.AGENT_TABS.TOOLS.INACTIVE')
                }}
              </span>
            </div>
            <p v-if="tool.url" class="mt-2 text-xs text-n-slate-10">
              <span
                class="rounded bg-n-alpha-2 px-1.5 py-0.5 font-mono text-xs"
              >
                {{ tool.method || 'POST' }}
              </span>
              <span class="ml-1 font-mono">{{ tool.url }}</span>
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- MCP Configuration -->
    <div
      class="overflow-hidden rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-5 py-3"
      >
        <div class="flex items-center gap-2">
          <i class="i-lucide-plug size-4 text-n-brand" />
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_SERVERS') }}
          </h3>
        </div>
      </div>
      <div class="p-5">
        <p class="mb-4 text-sm text-n-slate-10">
          {{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_DESCRIPTION') }}
        </p>
        <!-- JSON template -->
        <div class="overflow-hidden rounded-lg border border-n-weak">
          <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <div
            class="flex items-center justify-between border-b border-n-weak bg-n-alpha-1 px-3 py-2"
          >
            <span class="font-mono text-xs text-n-slate-10">
              mcp_config.json
            </span>
            <button
              class="flex items-center gap-1 text-xs text-n-slate-10 transition-colors hover:text-n-slate-12"
              @click="copyMcpTemplate"
            >
              <i
                :class="
                  copiedMcp
                    ? 'i-lucide-check size-3 text-green-600'
                    : 'i-lucide-clipboard size-3'
                "
              />
              {{ copiedMcp ? 'Copiado!' : 'Copiar' }}
            </button>
          </div>
          <!-- eslint-enable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
          <!-- eslint-disable prettier/prettier -->
          <pre class="max-h-48 overflow-x-auto bg-slate-950 p-3 font-mono text-xs text-slate-300">{{ mcpTemplate }}</pre>
          <!-- eslint-enable prettier/prettier -->
        </div>
        <!-- Docs link -->
        <div class="mt-4 flex items-start gap-2 rounded-lg bg-n-alpha-1 p-3">
          <i class="i-lucide-info mt-0.5 size-4 shrink-0 text-n-slate-10" />
          <div class="text-xs text-n-slate-10">
            <p class="mb-1 font-medium text-n-slate-11">
              {{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_HOW_TO') }}
            </p>
            <ol class="list-inside list-decimal space-y-1">
              <li>{{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_STEP_1') }}</li>
              <li>{{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_STEP_2') }}</li>
              <li>{{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_STEP_3') }}</li>
              <li>{{ t('CAPTAIN.AGENT_TABS.TOOLS.MCP_STEP_4') }}</li>
            </ol>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
