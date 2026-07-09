<script setup>
// Painel "Execuções"/Logs — o que o botão "Execuções" abre no canvas. Lê GET flows/:id/logs
// (os flow_step_logs, um por nó executado no disparo REAL) e lista, mais recentes primeiro:
// status colorido (sucesso/falha/pulado), o passo, o ramo, a duração, o error_code legível e
// quando aconteceu. Paginação simples via "carregar mais". Estado vazio quando nunca rodou.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { labelForNode, iconForNode } from './nodeCatalog';

const props = defineProps({
  flowId: {
    type: [String, Number],
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const isLoading = ref(true);
const hasError = ref(false);
const logs = ref([]);
const currentPage = ref(1);
const totalPages = ref(1);
const totalCount = ref(0);

const STATUS_META = {
  success: {
    tone: 'bg-n-teal-3 text-n-teal-11',
    icon: 'i-lucide-check',
    labelKey: 'AUTOMATION.CANVAS.LOGS.STATUS.SUCCESS',
  },
  failed: {
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    icon: 'i-lucide-x',
    labelKey: 'AUTOMATION.CANVAS.LOGS.STATUS.FAILED',
  },
  skipped: {
    tone: 'bg-n-amber-3 text-n-amber-11',
    icon: 'i-lucide-minus',
    labelKey: 'AUTOMATION.CANVAS.LOGS.STATUS.SKIPPED',
  },
};

const statusMeta = status => STATUS_META[status] || STATUS_META.skipped;

// Rótulo do passo: ação → nome localizado (nodeCatalog); decisão (só branch_key) → "Decisão";
// senão o node_id cru. Ícone idem — ação usa o do catálogo, decisão usa git-branch.
const logLabel = log => {
  if (log.action_name)
    return t(labelForNode({ type: 'action', action_name: log.action_name }));
  if (log.branch_key != null) return t('AUTOMATION.CANVAS.LOGS.BRANCH_STEP');
  return log.node_id || t('AUTOMATION.CANVAS.LOGS.UNKNOWN_STEP');
};

const logIcon = log =>
  log.action_name
    ? iconForNode({ type: 'action', action_name: log.action_name })
    : 'i-lucide-git-branch';

const formatDuration = ms => {
  if (ms == null) return '—';
  if (ms < 1000) return `${ms} ms`;
  return `${(ms / 1000).toFixed(1)} s`;
};

const formatTime = epoch => {
  if (!epoch) return '';
  const date = new Date(epoch * 1000);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleString();
};

const fetchLogs = async (page = 1) => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const data = await store.dispatch('flows/getLogs', {
      id: props.flowId,
      page,
    });
    const payload = data.payload || [];
    logs.value = page > 1 ? [...logs.value, ...payload] : payload;
    currentPage.value = data.meta?.current_page || page;
    totalPages.value = data.meta?.total_pages || 1;
    totalCount.value = data.meta?.total_count ?? logs.value.length;
  } catch (error) {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const hasMore = computed(() => currentPage.value < totalPages.value);
const isInitialLoading = computed(
  () => isLoading.value && logs.value.length === 0
);
const loadMore = () => fetchLogs(currentPage.value + 1);
const refresh = () => fetchLogs(1);

onMounted(() => fetchLogs(1));
</script>

<template>
  <div class="fixed inset-0 z-50 flex" data-testid="logs-panel">
    <div
      class="absolute inset-0 bg-n-alpha-black2 backdrop-blur-[1px]"
      @click="emit('close')"
    />
    <aside
      class="relative z-10 flex flex-col w-full h-full ml-auto shadow-xl max-w-[520px] bg-n-solid-1 border-l border-n-weak"
    >
      <header
        class="flex items-center gap-3 px-4 border-b h-14 shrink-0 border-n-weak"
      >
        <span
          class="grid rounded-lg size-8 place-items-center bg-n-alpha-1 text-n-slate-11"
        >
          <span class="i-lucide-scroll-text" />
        </span>
        <div class="flex flex-col min-w-0">
          <span class="text-sm font-semibold truncate text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.LOGS.TITLE') }}
          </span>
          <span v-if="totalCount" class="text-xs truncate text-n-slate-11">
            {{ t('AUTOMATION.CANVAS.LOGS.COUNT', { count: totalCount }) }}
          </span>
        </div>
        <button
          class="ml-auto text-n-slate-11 hover:text-n-slate-12 shrink-0"
          :aria-label="t('AUTOMATION.CANVAS.LOGS.REFRESH')"
          data-testid="logs-refresh"
          @click="refresh"
        >
          <span
            class="i-lucide-refresh-cw"
            :class="{ 'animate-spin': isLoading }"
          />
        </button>
        <button
          class="text-n-slate-11 hover:text-n-slate-12 shrink-0"
          :aria-label="t('AUTOMATION.CANVAS.CONFIG.CLOSE')"
          data-testid="logs-close"
          @click="emit('close')"
        >
          <span class="i-lucide-x" />
        </button>
      </header>

      <div class="flex-1 min-h-0 p-4 overflow-y-auto">
        <!-- Carregando (1ª página) -->
        <div
          v-if="isInitialLoading"
          class="flex flex-col items-center justify-center gap-2 py-10 text-n-slate-10"
        >
          <span class="text-2xl i-lucide-loader-circle animate-spin" />
          <p class="text-sm">{{ t('AUTOMATION.CANVAS.LOGS.LOADING') }}</p>
        </div>

        <!-- Erro -->
        <div
          v-else-if="hasError"
          class="flex flex-col items-center gap-3 py-10 text-center"
        >
          <span class="text-2xl i-lucide-triangle-alert text-n-ruby-9" />
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.LOGS.ERROR') }}
          </p>
          <button
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-12 bg-n-solid-3 hover:bg-n-solid-4"
            @click="refresh"
          >
            {{ t('AUTOMATION.CANVAS.LOGS.RETRY') }}
          </button>
        </div>

        <!-- Vazio: nunca rodou -->
        <div
          v-else-if="!logs.length"
          class="flex flex-col items-center gap-2 py-10 text-center text-n-slate-10"
          data-testid="logs-empty"
        >
          <span class="text-2xl i-lucide-history" />
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.LOGS.EMPTY') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('AUTOMATION.CANVAS.LOGS.EMPTY_HINT') }}
          </p>
        </div>

        <!-- Lista de step-logs -->
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="log in logs"
            :key="log.id"
            class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-solid-2"
            data-testid="logs-row"
          >
            <div class="flex items-center gap-2">
              <span
                class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] font-semibold shrink-0"
                :class="statusMeta(log.status).tone"
              >
                <span :class="statusMeta(log.status).icon" />
                {{ t(statusMeta(log.status).labelKey) }}
              </span>
              <span
                class="text-base shrink-0 text-n-slate-10"
                :class="logIcon(log)"
              />
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ logLabel(log) }}
              </span>
              <span
                class="ml-auto text-xs shrink-0 text-n-slate-10 tabular-nums"
              >
                {{ formatDuration(log.duration_ms) }}
              </span>
            </div>

            <div
              class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-n-slate-10"
            >
              <span v-if="log.node_id" class="font-mono">{{
                log.node_id
              }}</span>
              <span
                v-if="log.branch_key"
                class="inline-flex items-center gap-1"
              >
                <span class="i-lucide-git-branch" />
                {{ log.branch_key }}
              </span>
              <span>{{ formatTime(log.created_at) }}</span>
            </div>

            <!-- Detalhe de falha: error_code legível + mensagem -->
            <div
              v-if="
                log.status === 'failed' && (log.error_code || log.error_message)
              "
              class="flex flex-col gap-0.5 p-2 rounded bg-n-ruby-2 text-n-ruby-11"
            >
              <span
                v-if="log.error_code"
                class="text-[11px] font-mono font-semibold"
              >
                {{ log.error_code }}
              </span>
              <span v-if="log.error_message" class="text-[11px] leading-snug">
                {{ log.error_message }}
              </span>
            </div>
          </li>
        </ul>

        <button
          v-if="hasMore && !hasError"
          class="w-full py-2 mt-3 text-xs font-medium rounded-lg text-n-slate-11 bg-n-solid-2 hover:bg-n-solid-3 disabled:opacity-60"
          :disabled="isLoading"
          data-testid="logs-load-more"
          @click="loadMore"
        >
          {{ t('AUTOMATION.CANVAS.LOGS.LOAD_MORE') }}
        </button>
      </div>
    </aside>
  </div>
</template>
