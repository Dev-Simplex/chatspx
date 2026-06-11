<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';

const EVENT_TYPES = [
  { value: '', label: 'All' },
  { value: 'response', label: 'Response' },
  { value: 'debounce_skip', label: 'Debounce Skip' },
  { value: 'debounce_fire', label: 'Debounce Fire' },
  { value: 'router_skip', label: 'Router Skip' },
  { value: 'business_hours_skip', label: 'Business Hours Skip' },
  { value: 'handoff', label: 'Handoff' },
  { value: 'media_process', label: 'Media Process' },
  { value: 'humanizer_split', label: 'Humanizer Split' },
  { value: 'dedup_skip', label: 'Dedup Skip' },
  { value: 'error', label: 'Error' },
  { value: 'copilot_trigger', label: 'Copilot Trigger' },
];

const EVENT_TYPE_COLORS = {
  response: 'bg-green-100 text-green-800',
  debounce_skip: 'bg-cyan-100 text-cyan-800',
  debounce_fire: 'bg-cyan-100 text-cyan-800',
  router_skip: 'bg-amber-100 text-amber-800',
  business_hours_skip: 'bg-purple-100 text-purple-800',
  handoff: 'bg-red-100 text-red-800',
  media_process: 'bg-indigo-100 text-indigo-800',
  humanizer_split: 'bg-pink-100 text-pink-800',
  dedup_skip: 'bg-orange-100 text-orange-800',
  error: 'bg-red-100 text-red-800',
  copilot_trigger: 'bg-violet-100 text-violet-800',
};

const store = useStore();
const route = useRoute();
const selectedEventType = ref('');
const page = ref(1);
let refreshInterval = null;

const assistantId = computed(() => route.params.assistantId);
const logs = computed(() => store.getters['captainAssistantLogs/getLogs']);
const meta = computed(() => store.getters['captainAssistantLogs/getMeta']);
const isFetching = computed(
  () => store.getters['captainAssistantLogs/getUIFlags'].isFetching
);

function fetchLogs() {
  store.dispatch('captainAssistantLogs/fetch', {
    page: page.value,
    assistantId: assistantId.value,
    eventType: selectedEventType.value || undefined,
  });
}

function formatTimestamp(ts) {
  return new Date(ts * 1000).toLocaleString();
}

watch([selectedEventType, page], () => fetchLogs());

onMounted(() => {
  fetchLogs();
  refreshInterval = setInterval(fetchLogs, 10000);
});

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval);
});
</script>

<template>
  <div class="flex flex-col gap-4 p-4">
    <div class="flex items-center gap-4">
      <h3 class="text-lg font-semibold text-ash-800">
        {{ $t('CAPTAIN.LOGS.TITLE') }}
      </h3>
      <select
        v-model="selectedEventType"
        class="rounded border border-ash-200 px-2 py-1 text-sm"
      >
        <option
          v-for="type in EVENT_TYPES"
          :key="type.value"
          :value="type.value"
        >
          {{ type.label }}
        </option>
      </select>
    </div>

    <div v-if="isFetching" class="py-8 text-center text-sm text-ash-500">
      Loading...
    </div>

    <table v-else class="w-full text-sm">
      <thead>
        <tr class="border-b border-ash-200 text-left text-xs text-ash-500">
          <th class="px-2 py-2">Event</th>
          <th class="px-2 py-2">Conversation</th>
          <th class="px-2 py-2">Payload</th>
          <th class="px-2 py-2">Duration</th>
          <th class="px-2 py-2">Timestamp</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="log in logs"
          :key="log.id"
          class="border-b border-ash-100 hover:bg-ash-25"
        >
          <td class="px-2 py-2">
            <span
              class="rounded-full px-2 py-0.5 text-xs font-medium"
              :class="
                EVENT_TYPE_COLORS[log.event_type] || 'bg-ash-100 text-ash-700'
              "
            >
              {{ log.event_type }}
            </span>
          </td>
          <td class="px-2 py-2 text-ash-700">
            {{ log.conversation_id || '-' }}
          </td>
          <td class="max-w-xs truncate px-2 py-2 text-ash-600">
            {{ JSON.stringify(log.payload) }}
          </td>
          <td class="px-2 py-2 text-ash-600">
            {{ log.duration_ms ? `${log.duration_ms}ms` : '-' }}
          </td>
          <td class="px-2 py-2 text-ash-500">
            {{ formatTimestamp(log.created_at) }}
          </td>
        </tr>
      </tbody>
    </table>

    <div
      v-if="meta.total_pages > 1"
      class="flex items-center justify-center gap-2"
    >
      <button
        :disabled="page <= 1"
        class="rounded border px-3 py-1 text-sm disabled:opacity-50"
        @click="page -= 1"
      >
        &larr;
      </button>
      <span class="text-sm text-ash-600">
        {{ meta.current_page }} / {{ meta.total_pages }}
      </span>
      <button
        :disabled="page >= meta.total_pages"
        class="rounded border px-3 py-1 text-sm disabled:opacity-50"
        @click="page += 1"
      >
        &rarr;
      </button>
    </div>
  </div>
</template>
