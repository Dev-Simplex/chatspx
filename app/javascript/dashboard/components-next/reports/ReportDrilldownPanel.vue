<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { formatDuration } from 'dashboard/helper/reportFormat';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import ReportsAPI from 'dashboard/api/reports';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

// As conversas por tras de um numero do relatorio: a lista sai do mesmo recorte que calcula o numero
// (V2::Reports::Conversations::DrilldownBuilder), entao o total do painel e o do cartao sempre batem.
const props = defineProps({
  // { key, name }: a metrica do cartao clicado
  metric: { type: Object, required: true },
  // { from, to, type, id, businessHours, inboxId }: os mesmos filtros da tela
  filters: { type: Object, required: true },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const route = useRoute();

const TIME_METRICS = [
  'avg_first_response_time',
  'avg_first_response_time_after_assignment',
  'avg_resolution_time',
  'reply_time',
  'resolutions_count',
];
const MESSAGE_METRICS = ['incoming_messages_count', 'outgoing_messages_count'];

const rows = ref([]);
const meta = ref(null);
const page = ref(1);
const isLoading = ref(false);
const hasError = ref(false);

const hasMore = computed(
  () => meta.value && page.value * meta.value.per_page < meta.value.total_count
);

const isMessageMetric = computed(() =>
  MESSAGE_METRICS.includes(props.metric.key)
);

const subtitle = computed(() => {
  if (!meta.value) return '';
  const { total_count: total, conversations_count: conversations } = meta.value;
  if (props.metric.key === 'conversations_count') {
    return t('REPORT.DRILLDOWN.TOTAL_CONVERSATIONS', { count: total });
  }
  if (isMessageMetric.value) {
    return t('REPORT.DRILLDOWN.TOTAL_MESSAGES', { total, conversations });
  }
  return t('REPORT.DRILLDOWN.TOTAL_EVENTS', { total, conversations });
});

const orderHint = computed(() => {
  if (props.metric.key === 'resolutions_count')
    return t('REPORT.DRILLDOWN.ORDER.RECENT');
  if (TIME_METRICS.includes(props.metric.key))
    return t('REPORT.DRILLDOWN.ORDER.SLOWEST');
  if (isMessageMetric.value) return t('REPORT.DRILLDOWN.ORDER.MOST_MESSAGES');
  return t('REPORT.DRILLDOWN.ORDER.RECENT');
});

const formatValue = row => {
  if (row.value === null || row.value === undefined) return '';
  if (isMessageMetric.value) {
    return t('REPORT.DRILLDOWN.MESSAGES_COUNT', { count: row.value });
  }
  return formatDuration(row.value, t);
};

const formatDate = timestamp =>
  timestamp ? format(fromUnixTime(timestamp), 'dd/MM/yyyy HH:mm') : '';

const STATUS_CLASSES = {
  open: 'bg-n-teal-3 text-n-teal-11',
  resolved: 'bg-n-slate-3 text-n-slate-11',
  pending: 'bg-n-amber-3 text-n-amber-11',
  snoozed: 'bg-n-blue-3 text-n-blue-11',
};

const conversationPath = row =>
  `/app/accounts/${route.params.accountId}/conversations/${row.display_id}`;

const fetchPage = async number => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReportsAPI.getDrilldown({
      ...props.filters,
      metric: props.metric.key,
      page: number,
    });
    meta.value = data.meta;
    rows.value = number === 1 ? data.payload : [...rows.value, ...data.payload];
    page.value = number;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const downloadCsv = async () => {
  try {
    const { data } = await ReportsAPI.getDrilldownCsv({
      ...props.filters,
      metric: props.metric.key,
    });
    downloadCsvFile(`${props.metric.key}.csv`, data);
  } catch {
    useAlert(t('REPORT.DRILLDOWN.CSV_FAILED'));
  }
};

const onKeydown = event => {
  if (event.key === 'Escape') emit('close');
};

// Pelo conteudo: a tela recria o objeto de filtros a cada render, e isso nao e filtro novo.
watch(
  () => JSON.stringify([props.metric.key, props.filters]),
  () => fetchPage(1)
);

onMounted(() => {
  fetchPage(1);
  document.addEventListener('keydown', onKeydown);
});
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 flex justify-end">
      <div class="absolute inset-0 bg-n-black/40" @click="emit('close')" />
      <aside
        class="relative flex flex-col w-full max-w-lg h-full bg-n-solid-2 border-l border-n-weak shadow-xl"
        role="dialog"
        :aria-label="metric.name"
      >
        <header
          class="flex items-start justify-between gap-3 px-5 py-4 border-b border-n-weak"
        >
          <div class="flex flex-col gap-1 min-w-0">
            <h2 class="text-base font-semibold text-n-slate-12 truncate">
              {{ metric.name }}
            </h2>
            <p class="text-sm text-n-slate-11">{{ subtitle }}</p>
            <p v-if="meta" class="text-xs text-n-slate-10">{{ orderHint }}</p>
          </div>
          <div class="flex items-center gap-1 shrink-0">
            <Button
              v-if="meta?.total_count"
              :label="$t('REPORT.DRILLDOWN.DOWNLOAD_CSV')"
              icon="i-lucide-download"
              variant="faded"
              color="slate"
              size="sm"
              @click="downloadCsv"
            />
            <Button
              icon="i-lucide-x"
              variant="ghost"
              color="slate"
              size="sm"
              :aria-label="$t('REPORT.DRILLDOWN.CLOSE')"
              @click="emit('close')"
            />
          </div>
        </header>

        <div class="flex-1 overflow-y-auto">
          <div
            v-if="isLoading && !rows.length"
            class="flex justify-center py-10"
          >
            <Spinner />
          </div>
          <p
            v-else-if="hasError"
            class="px-5 py-10 text-sm text-center text-n-ruby-11"
          >
            {{ $t('REPORT.DRILLDOWN.FETCH_FAILED') }}
          </p>
          <p
            v-else-if="!rows.length"
            class="px-5 py-10 text-sm text-center text-n-slate-10"
          >
            {{ $t('REPORT.DRILLDOWN.EMPTY') }}
          </p>
          <ul v-else class="divide-y divide-n-weak">
            <li v-for="(row, index) in rows" :key="`${row.id}-${index}`">
              <a
                :href="conversationPath(row)"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-start justify-between gap-3 px-5 py-3 transition-colors hover:bg-n-alpha-1"
              >
                <div class="flex flex-col gap-0.5 min-w-0">
                  <span class="text-sm font-medium text-n-slate-12 truncate">
                    #{{ row.display_id }} ·
                    {{ row.contact_name || $t('REPORT.DRILLDOWN.NO_NAME') }}
                  </span>
                  <span class="text-xs text-n-slate-11 truncate">
                    {{
                      [
                        row.inbox_name,
                        row.agent_name || $t('REPORT.DRILLDOWN.NO_AGENT'),
                        row.team_name,
                      ]
                        .filter(Boolean)
                        .join(' · ')
                    }}
                  </span>
                  <span class="text-xs text-n-slate-10">
                    {{ formatDate(row.value_at || row.created_at) }}
                  </span>
                </div>
                <div class="flex flex-col items-end gap-1 shrink-0">
                  <span
                    v-if="formatValue(row)"
                    class="text-sm font-semibold text-n-slate-12 tabular-nums"
                  >
                    {{ formatValue(row) }}
                  </span>
                  <span
                    class="px-2 py-0.5 text-xs font-medium rounded-full"
                    :class="STATUS_CLASSES[row.status] || STATUS_CLASSES.open"
                  >
                    {{ $t(`REPORT.DRILLDOWN.STATUS.${row.status}`) }}
                  </span>
                </div>
              </a>
            </li>
          </ul>
        </div>

        <footer
          v-if="hasMore"
          class="flex justify-center px-5 py-3 border-t border-n-weak"
        >
          <Button
            :label="$t('REPORT.DRILLDOWN.LOAD_MORE')"
            variant="faded"
            color="slate"
            size="sm"
            :is-loading="isLoading"
            @click="fetchPage(page + 1)"
          />
        </footer>
      </aside>
    </div>
  </Teleport>
</template>
