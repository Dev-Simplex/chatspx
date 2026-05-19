<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const scenarios = computed(() => store.getters['captainScenarios/getRecords']);
const isFetching = computed(
  () => store.getters['captainScenarios/getUIFlags'].fetchingList
);

const messageInput = ref('');
const messageHistory = ref([]);
const isSending = ref(false);

// --- Estado de edicao/criacao ---
const expandedId = ref(null);
const editingId = ref(null);
const editForm = ref({ title: '', description: '', instruction: '' });
const saving = ref(false);

const showCreateForm = ref(false);
const createForm = ref({ title: '', description: '', instruction: '' });

function toggleExpand(id) {
  expandedId.value = expandedId.value === id ? null : id;
}

function startEdit(scenario) {
  editingId.value = scenario.id;
  editForm.value = {
    title: scenario.title || '',
    description: scenario.description || '',
    instruction: scenario.instruction || '',
  };
}

function cancelEdit() {
  editingId.value = null;
}

async function saveEdit(id) {
  if (saving.value) return;
  saving.value = true;
  try {
    await store.dispatch('captainScenarios/update', {
      id,
      assistantId: assistantId.value,
      title: editForm.value.title,
      description: editForm.value.description,
      instruction: editForm.value.instruction,
    });
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVED'));
    editingId.value = null;
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}

async function createScenario() {
  if (
    !createForm.value.title.trim() ||
    !createForm.value.instruction.trim() ||
    saving.value
  ) {
    return;
  }
  saving.value = true;
  try {
    await store.dispatch('captainScenarios/create', {
      assistantId: assistantId.value,
      title: createForm.value.title.trim(),
      description: createForm.value.description.trim(),
      instruction: createForm.value.instruction.trim(),
    });
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.CREATED'));
    createForm.value = { title: '', description: '', instruction: '' };
    showCreateForm.value = false;
    store.dispatch('captainScenarios/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}

async function deleteScenario(id) {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN.AGENT_TABS.SCENARIOS.CONFIRM_DELETE'))) return;
  try {
    await store.dispatch('captainScenarios/delete', {
      id,
      assistantId: assistantId.value,
    });
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.DELETED'));
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE_ERROR'));
  }
}

onMounted(() => {
  store.dispatch('captainScenarios/get', {
    assistantId: assistantId.value,
  });
});

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content || isSending.value) return;

  messageHistory.value.push({ role: 'user', content });
  messageInput.value = '';
  isSending.value = true;

  try {
    const { data } = await CaptainAssistantAPI.playground({
      assistantId: assistantId.value,
      messageContent: content,
      messageHistory: messageHistory.value.slice(0, -1),
    });
    messageHistory.value.push({
      role: 'assistant',
      content: data.message || data.response || '',
    });
  } catch {
    messageHistory.value.push({
      role: 'assistant',
      content: 'Erro ao processar mensagem.',
    });
  } finally {
    isSending.value = false;
  }
}
</script>

<template>
  <div class="flex h-full flex-col gap-4 p-6 lg:flex-row">
    <!-- Scenarios list -->
    <div class="w-full space-y-3 overflow-y-auto lg:w-1/2">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('AGENT_DETAIL.TABS.SCENARIOS') }}
        </h3>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-2.5 py-1 text-xs font-medium text-white transition-colors hover:brightness-95"
          @click="showCreateForm = !showCreateForm"
        >
          <i class="i-lucide-plus size-3" />
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.ADD') }}
        </button>
      </div>

      <!-- Create form -->
      <div
        v-if="showCreateForm"
        class="space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
      >
        <input
          v-model="createForm.title"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.SCENARIOS.TITLE_PLACEHOLDER')"
        />
        <input
          v-model="createForm.description"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.SCENARIOS.DESCRIPTION_PLACEHOLDER')
          "
        />
        <textarea
          v-model="createForm.instruction"
          rows="5"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.SCENARIOS.INSTRUCTION_PLACEHOLDER')
          "
        />
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
            :disabled="saving"
            @click="createScenario"
          >
            {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="showCreateForm = false"
          >
            {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.CANCEL') }}
          </button>
        </div>
      </div>

      <div
        v-if="isFetching"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <i class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.LOADING') }}
      </div>
      <div v-else-if="!scenarios.length" class="py-16 text-center">
        <i class="i-lucide-crosshair mx-auto mb-4 size-12 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.NO_SCENARIOS') }}
        </p>
      </div>
      <div
        v-for="scenario in scenarios"
        :key="scenario.id"
        class="rounded-xl border border-n-weak bg-white dark:bg-n-solid-2"
      >
        <!-- View mode -->
        <div v-if="editingId !== scenario.id">
          <button
            type="button"
            class="flex w-full items-start justify-between gap-2 p-4 text-left"
            @click="toggleExpand(scenario.id)"
          >
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-n-slate-12">
                {{ scenario.title }}
              </p>
              <p
                v-if="scenario.description"
                class="mt-0.5 text-sm text-n-slate-10"
              >
                {{ scenario.description }}
              </p>
            </div>
            <i
              class="size-4 shrink-0 text-n-slate-9"
              :class="
                expandedId === scenario.id
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </button>

          <div
            v-if="expandedId === scenario.id"
            class="border-t border-n-weak px-4 py-3"
          >
            <p class="mb-1 text-xs font-semibold text-n-slate-11">
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.INSTRUCTION_LABEL') }}
            </p>
            <pre
              class="mb-3 max-h-64 overflow-auto whitespace-pre-wrap rounded-lg bg-n-alpha-1 p-3 text-xs text-n-slate-11"
              >{{ scenario.instruction }}</pre
            >
            <div v-if="scenario.tools && scenario.tools.length" class="mb-3">
              <p class="mb-1 text-xs font-semibold text-n-slate-11">
                {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.TOOLS_LABEL') }}
              </p>
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="tool in scenario.tools"
                  :key="tool"
                  class="rounded-md bg-n-alpha-2 px-2 py-0.5 font-mono text-xs text-n-slate-11"
                >
                  {{ tool }}
                </span>
              </div>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-12 transition-colors hover:bg-n-alpha-3"
                @click="startEdit(scenario)"
              >
                <i class="i-lucide-pencil size-3" />
                {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.EDIT') }}
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs text-red-600 transition-colors hover:bg-red-50 dark:hover:bg-red-900/20"
                @click="deleteScenario(scenario.id)"
              >
                <i class="i-lucide-trash-2 size-3" />
                {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.DELETE') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Edit mode -->
        <div v-else class="space-y-2 p-4">
          <input
            v-model="editForm.title"
            type="text"
            class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
            :placeholder="t('CAPTAIN.AGENT_TABS.SCENARIOS.TITLE_PLACEHOLDER')"
          />
          <input
            v-model="editForm.description"
            type="text"
            class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
            :placeholder="
              t('CAPTAIN.AGENT_TABS.SCENARIOS.DESCRIPTION_PLACEHOLDER')
            "
          />
          <textarea
            v-model="editForm.instruction"
            rows="8"
            class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
            :placeholder="
              t('CAPTAIN.AGENT_TABS.SCENARIOS.INSTRUCTION_PLACEHOLDER')
            "
          />
          <div class="flex gap-2">
            <button
              type="button"
              class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
              :disabled="saving"
              @click="saveEdit(scenario.id)"
            >
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE') }}
            </button>
            <button
              type="button"
              class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
              @click="cancelEdit"
            >
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.CANCEL') }}
            </button>
          </div>
          <p class="text-xs text-n-slate-9">
            {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.TOOLS_HINT') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Playground -->
    <div
      class="flex w-full flex-col rounded-xl border border-n-weak bg-white dark:bg-n-solid-2 lg:w-1/2"
    >
      <div class="flex items-center gap-2 border-b border-n-weak px-4 py-3">
        <i class="i-lucide-play size-4 text-n-slate-11" />
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.PLAYGROUND') }}
        </h3>
      </div>
      <div class="flex-1 space-y-3 overflow-y-auto p-4">
        <div
          v-for="(msg, idx) in messageHistory"
          :key="idx"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[80%] rounded-2xl px-3 py-2 text-sm"
            :class="
              msg.role === 'user'
                ? 'rounded-br-sm bg-n-brand text-white'
                : 'rounded-bl-sm bg-n-alpha-2 text-n-slate-12'
            "
          >
            {{ msg.content }}
          </div>
        </div>
        <div
          v-if="isSending"
          class="flex items-center gap-2 text-sm text-n-slate-10"
        >
          <i class="i-lucide-loader-2 size-3.5 animate-spin" />
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.THINKING') }}
        </div>
      </div>
      <div class="flex gap-2 border-t border-n-weak p-3">
        <input
          v-model="messageInput"
          class="flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
          :placeholder="t('CAPTAIN.AGENT_TABS.SCENARIOS.MESSAGE_PLACEHOLDER')"
          @keyup.enter="sendMessage"
        />
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white transition-colors hover:brightness-95"
          :disabled="isSending"
          @click="sendMessage"
        >
          <i class="i-lucide-send size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SEND') }}
        </button>
      </div>
    </div>
  </div>
</template>
