<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const logs = computed(() => store.getters['captainAssistantLogs/getLogs']);
const meta = computed(() => store.getters['captainAssistantLogs/getMeta']);
const isFetching = computed(
  () => store.getters['captainAssistantLogs/getUIFlags'].isFetching
);

const filterType = ref('');
const currentPage = ref(1);
let refreshInterval = null;

// Espelha Captain::AssistantLog::EVENT_TYPES (drift de 'debounce'/'copilot'/'inbox'
// corrigido na Fase E/E4 — esses valores nunca existiram no backend).
const eventTypeConfig = {
  response: { color: 'bg-green-500', icon: 'i-lucide-check-circle' },
  debounce_skip: { color: 'bg-cyan-500', icon: 'i-lucide-timer-off' },
  debounce_fire: { color: 'bg-cyan-500', icon: 'i-lucide-timer' },
  router_skip: { color: 'bg-amber-500', icon: 'i-lucide-skip-forward' },
  business_hours_skip: { color: 'bg-purple-500', icon: 'i-lucide-clock' },
  handoff: { color: 'bg-red-500', icon: 'i-lucide-user-check' },
  media_process: { color: 'bg-indigo-500', icon: 'i-lucide-image' },
  humanizer_split: { color: 'bg-pink-500', icon: 'i-lucide-split' },
  dedup_skip: { color: 'bg-orange-500', icon: 'i-lucide-copy-x' },
  error: { color: 'bg-red-500', icon: 'i-lucide-alert-circle' },
  copilot_trigger: { color: 'bg-violet-500', icon: 'i-lucide-sparkles' },
  // E4: auditoria da atribuição do espelho captain
  mirror_assigned: { color: 'bg-blue-500', icon: 'i-lucide-bot' },
  mirror_released: { color: 'bg-slate-500', icon: 'i-lucide-bot-off' },
  human_takeover: { color: 'bg-amber-500', icon: 'i-lucide-user-round-check' },
};

const eventTypes = ['', ...Object.keys(eventTypeConfig)];

function fetchLogs() {
  store.dispatch('captainAssistantLogs/fetch', {
    assistantId: assistantId.value,
    page: currentPage.value,
    event_type: filterType.value || undefined,
  });
}

function changeFilter(type) {
  filterType.value = type;
  currentPage.value = 1;
  fetchLogs();
}

function changePage(page) {
  currentPage.value = page;
  fetchLogs();
}

onMounted(() => {
  fetchLogs();
  refreshInterval = setInterval(fetchLogs, 10000);
});

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval);
});

function formatTimestamp(ts) {
  if (!ts) return '';
  return new Date(ts).toLocaleString('pt-BR');
}

function summarizePayload(payload) {
  if (!payload) return '';
  if (typeof payload === 'string') return payload;
  return JSON.stringify(payload).slice(0, 120);
}
</script>

<template>
  <div class="p-6">
    <div class="mb-4 flex items-center justify-between">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t('AGENT_DETAIL.TABS.LOGS') }}
      </h3>
      <select
        :value="filterType"
        class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus:ring-1 focus:ring-n-brand dark:bg-n-solid-3"
        @change="changeFilter($event.target.value)"
      >
        <option value="">
          {{ t('CAPTAIN.AGENT_TABS.LOGS.ALL') }}
        </option>
        <option v-for="et in eventTypes.slice(1)" :key="et" :value="et">
          {{ et }}
        </option>
      </select>
    </div>

    <div
      v-if="isFetching && !logs.length"
      class="flex items-center gap-2 text-sm text-n-slate-10"
    >
      <i class="i-lucide-loader-2 size-3.5 animate-spin" />
      {{ t('CAPTAIN.AGENT_TABS.LOGS.LOADING') }}
    </div>
    <div v-else-if="!logs.length" class="py-16 text-center">
      <i class="i-lucide-scroll-text mx-auto mb-4 size-12 text-n-slate-9" />
      <p class="text-base font-medium text-n-slate-12">
        {{ t('CAPTAIN.AGENT_TABS.LOGS.NO_LOGS') }}
      </p>
    </div>

    <div v-else class="space-y-2">
      <div
        v-for="log in logs"
        :key="log.id"
        class="flex items-start gap-3 rounded-xl border border-n-weak bg-white p-3 transition-colors duration-100 hover:bg-n-alpha-1 dark:bg-n-solid-2"
      >
        <div
          class="mt-0.5 flex size-6 items-center justify-center rounded-full"
          :class="
            (eventTypeConfig[log.event_type] || {}).color || 'bg-n-slate-8'
          "
        >
          <i
            class="size-3 text-white"
            :class="[
              (eventTypeConfig[log.event_type] || {}).icon || 'i-lucide-circle',
            ]"
          />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <span class="text-xs font-medium text-n-slate-12">
              {{ log.event_type }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ formatTimestamp(log.created_at) }}
            </span>
          </div>
          <p class="mt-0.5 truncate text-xs text-n-slate-10">
            {{ summarizePayload(log.payload) }}
          </p>
        </div>
      </div>
    </div>

    <!-- Pagination -->
    <div
      v-if="meta.total_pages > 1"
      class="mt-4 flex items-center justify-center gap-2"
    >
      <button
        v-for="page in meta.total_pages"
        :key="page"
        type="button"
        class="rounded-lg px-2.5 py-1 text-xs transition-colors"
        :class="
          page === currentPage
            ? 'bg-n-brand text-white'
            : 'text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12'
        "
        @click="changePage(page)"
      >
        {{ page }}
      </button>
    </div>
  </div>
</template>
