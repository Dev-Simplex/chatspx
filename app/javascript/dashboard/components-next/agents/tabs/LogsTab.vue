<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiPagination from 'dashboard/components-next/agents-ui/AiPagination.vue';

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

const eventTypeConfig = {
  response: { color: 'bg-green-500', icon: 'i-lucide-check-circle' },
  debounce_skip: { color: 'bg-n-teal-9', icon: 'i-lucide-timer-off' },
  debounce_fire: { color: 'bg-n-teal-9', icon: 'i-lucide-timer' },
  router_skip: { color: 'bg-n-amber-9', icon: 'i-lucide-skip-forward' },
  business_hours_skip: { color: 'bg-n-violet-9', icon: 'i-lucide-clock' },
  handoff: { color: 'bg-red-500', icon: 'i-lucide-user-check' },
  media_process: { color: 'bg-n-violet-10', icon: 'i-lucide-image' },
  humanizer_split: { color: 'bg-n-ruby-9', icon: 'i-lucide-split' },
  dedup_skip: { color: 'bg-n-amber-9', icon: 'i-lucide-copy-x' },
  error: { color: 'bg-red-500', icon: 'i-lucide-alert-circle' },
  copilot_trigger: { color: 'bg-violet-500', icon: 'i-lucide-sparkles' },
  mirror_assigned: { color: 'bg-n-blue-9', icon: 'i-lucide-bot' },
  mirror_released: { color: 'bg-slate-500', icon: 'i-lucide-bot-off' },
  human_takeover: { color: 'bg-n-amber-9', icon: 'i-lucide-user-round-check' },
};

const filterOptions = computed(() => [
  { value: '', label: t('CAPTAIN.AGENT_TABS.LOGS.ALL') },
  ...Object.keys(eventTypeConfig).map(et => ({ value: et, label: et })),
]);

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

// A API serializa `created_at` com `.to_i`, ou seja, EPOCH EM SEGUNDOS
// (assistant_logs/index.json.jbuilder). `new Date(segundos)` interpreta o número como
// milissegundos, então todo log aparecia datado de janeiro de 1970. Aceita também string
// de data e epoch já em milissegundos, para não depender do formato de um único endpoint.
const MS_THRESHOLD = 1e11;
function formatTimestamp(ts) {
  if (!ts) return '';
  if (typeof ts === 'number') {
    const ms = ts < MS_THRESHOLD ? ts * 1000 : ts;
    return new Date(ms).toLocaleString('pt-BR');
  }
  const parsed = new Date(ts);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toLocaleString('pt-BR');
}
function summarizePayload(payload) {
  if (!payload) return '';
  if (typeof payload === 'string') return payload;
  return JSON.stringify(payload).slice(0, 120);
}
const logStyle = type =>
  eventTypeConfig[type] || { color: 'bg-n-slate-8', icon: 'i-lucide-circle' };
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto max-w-3xl">
    <div class="flex justify-between items-center mb-4">
      <h3 class="text-[15px] font-bold text-n-slate-12">
        {{ t('AGENT_DETAIL.TABS.LOGS') }}
      </h3>
      <div class="w-52">
        <AiSelect
          :model-value="filterType"
          :options="filterOptions"
          @update:model-value="changeFilter"
        />
      </div>
    </div>

    <div
      v-if="isFetching && !logs.length"
      class="flex gap-2 items-center text-sm text-n-slate-10"
    >
      <span class="i-lucide-loader-2 size-3.5 animate-spin" />
      {{ t('CAPTAIN.AGENT_TABS.LOGS.LOADING') }}
    </div>
    <AiEmptyState
      v-else-if="!logs.length"
      icon="i-lucide-scroll-text"
      :title="t('CAPTAIN.AGENT_TABS.LOGS.NO_LOGS')"
    />

    <div v-else class="space-y-2">
      <div
        v-for="log in logs"
        :key="log.id"
        class="flex gap-3 items-start p-3 rounded-2xl border transition-colors border-n-weak bg-n-solid-1 hover:bg-n-alpha-1"
      >
        <span
          class="grid place-items-center mt-0.5 rounded-full size-6"
          :class="logStyle(log.event_type).color"
        >
          <span
            class="text-white size-3"
            :class="logStyle(log.event_type).icon"
          />
        </span>
        <div class="flex-1 min-w-0">
          <div class="flex gap-2 items-center">
            <span class="font-mono text-[12.5px] font-bold text-n-slate-12">
              {{ log.event_type }}
            </span>
            <span class="text-[11.5px] text-n-slate-10">
              {{ formatTimestamp(log.created_at) }}
            </span>
          </div>
          <p class="mt-0.5 font-mono text-[11.5px] truncate text-n-slate-10">
            {{ summarizePayload(log.payload) }}
          </p>
        </div>
      </div>
    </div>

    <AiPagination
      :page="currentPage"
      :total-pages="meta.total_pages || 1"
      @update:page="changePage"
    />
  </div>
</template>
