<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';

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

const expandedId = ref(null);
const editingId = ref(null);
const editForm = ref({ title: '', description: '', instruction: '' });
const saving = ref(false);

const showCreateForm = ref(false);
const createForm = ref({ title: '', description: '', instruction: '' });

const FIELD =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none transition focus:border-n-brand focus:ring-2 focus:ring-n-brand/30';

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
  store.dispatch('captainScenarios/get', { assistantId: assistantId.value });
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
  <div class="flex flex-col gap-4 px-6 pt-4 pb-10 h-full lg:flex-row">
    <!-- Cenários -->
    <div class="space-y-2.5 w-full lg:w-1/2">
      <div class="flex justify-between items-center px-1">
        <span
          class="text-[12.5px] font-bold tracking-wide uppercase text-n-slate-10"
        >
          {{ t('AGENT_DETAIL.TABS.SCENARIOS') }}
        </span>
        <AiButton variant="ghost" @click="showCreateForm = !showCreateForm">
          <span class="i-lucide-plus size-4" />
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.ADD') }}
        </AiButton>
      </div>

      <!-- Criar -->
      <div
        v-if="showCreateForm"
        class="p-4 space-y-2.5 rounded-2xl border border-n-weak bg-n-alpha-1"
      >
        <input
          v-model="createForm.title"
          type="text"
          :class="FIELD"
          :placeholder="t('CAPTAIN.AGENT_TABS.SCENARIOS.TITLE_PLACEHOLDER')"
        />
        <input
          v-model="createForm.description"
          type="text"
          :class="FIELD"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.SCENARIOS.DESCRIPTION_PLACEHOLDER')
          "
        />
        <textarea
          v-model="createForm.instruction"
          rows="5"
          :class="FIELD"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.SCENARIOS.INSTRUCTION_PLACEHOLDER')
          "
        />
        <div class="flex gap-2 justify-end">
          <AiButton variant="subtle" @click="showCreateForm = false">
            {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.CANCEL') }}
          </AiButton>
          <AiButton :disabled="saving" @click="createScenario">
            {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE') }}
          </AiButton>
        </div>
      </div>

      <div
        v-if="isFetching"
        class="flex gap-2 items-center px-1 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.LOADING') }}
      </div>
      <div
        v-else-if="!scenarios.length"
        class="py-14 text-center rounded-2xl border border-dashed border-n-weak bg-n-alpha-1"
      >
        <span class="mx-auto mb-3 i-lucide-crosshair size-9 text-n-slate-9" />
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.NO_SCENARIOS') }}
        </p>
      </div>

      <div
        v-for="scenario in scenarios"
        :key="scenario.id"
        class="rounded-2xl border shadow-sm border-n-weak bg-n-solid-1"
      >
        <div v-if="editingId !== scenario.id">
          <button
            type="button"
            class="flex gap-2 items-start p-4 w-full text-left"
            @click="toggleExpand(scenario.id)"
          >
            <span
              class="grid flex-none place-items-center mt-0.5 text-white rounded-[9px] bg-n-brand size-8"
            >
              <span class="i-lucide-git-branch size-4" />
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-[14px] font-bold text-n-slate-12">{{
                scenario.title
              }}</span>
              <span
                v-if="scenario.description"
                class="block mt-0.5 text-[12.5px] text-n-slate-11"
                >{{ scenario.description }}</span
              >
            </span>
            <span
              class="flex-none mt-1 size-4 text-n-slate-9"
              :class="
                expandedId === scenario.id
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </button>
          <div
            v-if="expandedId === scenario.id"
            class="px-4 py-3 border-t border-n-weak"
          >
            <p class="mb-1 text-xs font-semibold text-n-slate-11">
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.INSTRUCTION_LABEL') }}
            </p>
            <pre
              class="overflow-auto p-3 mb-3 max-h-64 text-xs whitespace-pre-wrap rounded-lg bg-n-alpha-1 text-n-slate-11"
              >{{ scenario.instruction }}</pre
            >
            <div class="flex gap-2">
              <AiButton variant="subtle" @click="startEdit(scenario)">
                <span class="i-lucide-pencil size-3.5" />
                {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.EDIT') }}
              </AiButton>
              <AiButton variant="danger" @click="deleteScenario(scenario.id)">
                <span class="i-lucide-trash-2 size-3.5" />
                {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.DELETE') }}
              </AiButton>
            </div>
          </div>
        </div>

        <div v-else class="p-4 space-y-2.5">
          <input v-model="editForm.title" type="text" :class="FIELD" />
          <input v-model="editForm.description" type="text" :class="FIELD" />
          <textarea v-model="editForm.instruction" rows="8" :class="FIELD" />
          <div class="flex gap-2 justify-end">
            <AiButton variant="subtle" @click="cancelEdit">
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.CANCEL') }}
            </AiButton>
            <AiButton :disabled="saving" @click="saveEdit(scenario.id)">
              {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SAVE') }}
            </AiButton>
          </div>
        </div>
      </div>
    </div>

    <!-- Testar (console estilo WhatsApp) -->
    <div
      class="flex flex-col w-full rounded-2xl border shadow-sm border-n-weak bg-n-solid-1 lg:w-1/2"
    >
      <div class="flex gap-2 items-center px-4 py-3 border-b border-n-weak">
        <span class="i-lucide-play size-4 text-n-brand" />
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.PLAYGROUND') }}
        </h3>
      </div>
      <div class="overflow-y-auto flex-1 p-4 space-y-2 min-h-[340px]">
        <div
          v-for="(msg, idx) in messageHistory"
          :key="idx"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[80%] px-3 py-2 text-sm rounded-2xl"
            :class="
              msg.role === 'user'
                ? 'rounded-br-sm bg-n-brand text-white'
                : 'rounded-bl-sm bg-n-alpha-2 text-n-slate-12'
            "
          >
            {{ msg.content }}
          </div>
        </div>
        <div v-if="isSending" class="flex justify-start">
          <div
            class="flex gap-1 items-center px-3 py-3 rounded-2xl rounded-bl-sm bg-n-alpha-2"
          >
            <span class="typing-dot" />
            <span class="typing-dot" />
            <span class="typing-dot" />
          </div>
        </div>
      </div>
      <div class="flex gap-2 p-3 border-t border-n-weak">
        <input
          v-model="messageInput"
          :class="FIELD"
          :placeholder="t('CAPTAIN.AGENT_TABS.SCENARIOS.MESSAGE_PLACEHOLDER')"
          @keyup.enter="sendMessage"
        />
        <AiButton :disabled="isSending" @click="sendMessage">
          <span class="i-lucide-send size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.SCENARIOS.SEND') }}
        </AiButton>
      </div>
    </div>
  </div>
</template>

<style scoped>
.typing-dot {
  width: 7px;
  height: 7px;
  border-radius: 9999px;
  background: #8b97a1;
  display: inline-block;
  animation: td-bounce 1s infinite;
}
.typing-dot:nth-child(2) {
  animation-delay: 0.15s;
}
.typing-dot:nth-child(3) {
  animation-delay: 0.3s;
}
@keyframes td-bounce {
  0%,
  80%,
  100% {
    transform: translateY(0);
    opacity: 0.5;
  }
  40% {
    transform: translateY(-5px);
    opacity: 1;
  }
}
@media (prefers-reduced-motion: reduce) {
  .typing-dot {
    animation: none;
  }
}
</style>
