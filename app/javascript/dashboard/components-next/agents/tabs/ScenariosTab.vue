<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const scenarios = computed(() => store.getters['captainScenarios/getRecords']);
const isFetching = computed(
  () => store.getters['captainScenarios/getUIFlags'].isFetching
);

const messageInput = ref('');
const messageHistory = ref([]);
const isSending = ref(false);

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
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('AGENT_DETAIL.TABS.SCENARIOS') }}
      </h3>
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
        class="rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ scenario.title }}
        </p>
        <p v-if="scenario.description" class="mt-0.5 text-sm text-n-slate-10">
          {{ scenario.description }}
        </p>
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
