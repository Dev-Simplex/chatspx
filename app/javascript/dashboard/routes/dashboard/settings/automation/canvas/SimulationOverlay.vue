<script setup>
// Overlay da SIMULAÇÃO (dry-run) do fluxo — o painel que o botão "Testar" abre. Chama
// POST flows/:id/simulate e renderiza, em ordem, os passos que o fluxo SEGUIRIA: o nó, o que
// FARIA (frase read-only vinda do backend) e, em condition/router, o RAMO tomado (destacado).
// Deixa explícito, o tempo todo, que é um ENSAIO A SECO: nada é enviado, nada é gravado. A
// simulação roda sobre a versão SALVA do fluxo (o backend lê flow.definition do banco).
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import {
  FAMILIES,
  familyForNode,
  labelForNode,
  iconForNode,
} from './nodeCatalog';

const props = defineProps({
  flowId: {
    type: [String, Number],
    required: true,
  },
  // Definition em memória — usada SÓ pra nomear as rotas do router nos ramos (espelha o
  // branchMeta do FlowCanvasView). Os passos em si são autoritativos do backend.
  definition: {
    type: Object,
    default: () => ({ nodes: [], edges: [] }),
  },
});

const emit = defineEmits(['close']);
const dialogRef = ref(null);

const { t } = useI18n();
const store = useStore();

const isLoading = ref(true);
const errorKind = ref(null); // null | 'no_conversation' | 'generic'
const steps = ref([]);
const sampleConversation = ref(null);

const TONE_CLASSES = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  slate: 'bg-n-slate-3 text-n-slate-11',
};

const nodeById = id =>
  (props.definition?.nodes || []).find(n => String(n.id) === String(id)) ||
  null;

// Metadados visuais do passo (ícone/cor/rótulo localizado), derivados de um nó sintético
// { type, action_name } — reusa o nodeCatalog, então fica consistente com o canvas.
const stepMeta = step => {
  const synthetic = { type: step.type, action_name: step.action_name };
  const family = FAMILIES[familyForNode(synthetic)] || FAMILIES.action;
  return {
    icon: iconForNode(synthetic),
    color: family.color,
    label: t(labelForNode(synthetic)),
  };
};

// Ramo tomado por um passo condition/router → { label, tone } pra o pill destacado. Reusa a
// definition (quando presente) pra nomear as rotas do router.
const branchInfo = step => {
  const branch = step.branch_key;
  if (branch == null) return null;
  if (step.type === 'condition') {
    if (String(branch) === 'true')
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.YES'),
        tone: 'teal',
      };
    if (String(branch) === 'false')
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.NO'),
        tone: 'ruby',
      };
  }
  const node = nodeById(step.node_id);
  if (node?.type === 'router') {
    const fallbackKey = String(node.fallback_key || 'fallback');
    if (String(branch) === fallbackKey)
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.ROUTER.FALLBACK'),
        tone: 'slate',
      };
    const routes = Array.isArray(node.routes) ? node.routes : [];
    const idx = routes.findIndex(r => String(r.key) === String(branch));
    if (idx >= 0)
      return {
        label:
          routes[idx].label ||
          t('AUTOMATION.CANVAS.CONFIG.ROUTER.ROUTE_N', { n: idx + 1 }),
        tone: 'amber',
      };
  }
  if (String(branch) === 'fallback')
    return {
      label: t('AUTOMATION.CANVAS.CONFIG.ROUTER.FALLBACK'),
      tone: 'slate',
    };
  return { label: String(branch), tone: 'amber' };
};

const runSimulation = async () => {
  isLoading.value = true;
  errorKind.value = null;
  try {
    const data = await store.dispatch('flows/simulate', { id: props.flowId });
    steps.value = data.steps || [];
    sampleConversation.value = data.conversation || null;
  } catch (error) {
    errorKind.value =
      error?.response?.status === 422 ? 'no_conversation' : 'generic';
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  dialogRef.value?.focus();
  runSimulation();
});
</script>

<template>
  <div
    ref="dialogRef"
    class="fixed inset-0 z-50 flex outline-none"
    role="dialog"
    aria-modal="true"
    :aria-label="t('AUTOMATION.CANVAS.SIMULATE.OPEN')"
    tabindex="-1"
    data-testid="simulation-overlay"
    @keydown.esc="emit('close')"
  >
    <div
      class="absolute inset-0 bg-n-alpha-black2 backdrop-blur-[1px]"
      @click="emit('close')"
    />
    <aside
      class="relative z-10 flex flex-col w-full h-full ml-auto shadow-xl max-w-[460px] bg-n-solid-1 border-l border-n-weak"
    >
      <header
        class="flex items-center gap-3 px-4 border-b h-14 shrink-0 border-n-weak"
      >
        <span
          class="grid rounded-lg size-8 place-items-center bg-n-alpha-1 text-n-brand"
        >
          <span class="i-lucide-flask-conical" />
        </span>
        <div class="flex flex-col min-w-0">
          <span class="text-sm font-semibold truncate text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.SIMULATE.TITLE') }}
          </span>
          <span
            v-if="sampleConversation"
            class="text-xs truncate text-n-slate-11"
          >
            {{
              t('AUTOMATION.CANVAS.SIMULATE.AGAINST', {
                name:
                  sampleConversation.contact_name ||
                  `#${sampleConversation.id}`,
              })
            }}
          </span>
        </div>
        <button
          class="ml-auto text-n-slate-11 hover:text-n-slate-12 shrink-0"
          :aria-label="t('AUTOMATION.CANVAS.CONFIG.CLOSE')"
          data-testid="simulation-close"
          @click="emit('close')"
        >
          <span class="i-lucide-x" />
        </button>
      </header>

      <!-- Faixa "modo simulação": vermelho/âmbar, ponto pulsante — deixa claro que nada saiu. -->
      <div
        class="flex flex-col gap-1 px-4 py-3 border-b shrink-0 border-n-weak bg-n-amber-2"
      >
        <span
          class="inline-flex items-center gap-2 text-[11px] font-bold tracking-wide uppercase text-n-amber-11"
        >
          <span class="relative flex size-2">
            <span
              class="absolute inline-flex w-full h-full rounded-full opacity-75 bg-n-ruby-9 animate-ping"
            />
            <span
              class="relative inline-flex rounded-full size-2 bg-n-ruby-9"
            />
          </span>
          {{ t('AUTOMATION.CANVAS.SIMULATE.MODE_BADGE') }}
        </span>
        <span class="text-xs leading-snug text-n-slate-11">
          {{ t('AUTOMATION.CANVAS.SIMULATE.MODE_HINT') }}
        </span>
      </div>

      <div class="flex-1 min-h-0 p-4 overflow-y-auto">
        <!-- Carregando -->
        <div
          v-if="isLoading"
          class="flex flex-col items-center justify-center gap-2 py-10 text-n-slate-10"
        >
          <span class="text-2xl i-lucide-loader-circle animate-spin" />
          <p class="text-sm">
            {{ t('AUTOMATION.CANVAS.SIMULATE.RUNNING') }}
          </p>
        </div>

        <!-- Sem conversa de amostra (422) -->
        <div
          v-else-if="errorKind === 'no_conversation'"
          class="flex flex-col items-center gap-3 py-10 text-center"
          data-testid="simulation-error-no-conversation"
        >
          <span
            class="text-2xl i-lucide-message-square-dashed text-n-slate-9"
          />
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.SIMULATE.NO_CONVERSATION') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('AUTOMATION.CANVAS.SIMULATE.NO_CONVERSATION_HINT') }}
          </p>
        </div>

        <!-- Erro genérico -->
        <div
          v-else-if="errorKind === 'generic'"
          class="flex flex-col items-center gap-3 py-10 text-center"
        >
          <span class="text-2xl i-lucide-triangle-alert text-n-ruby-9" />
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AUTOMATION.CANVAS.SIMULATE.ERROR') }}
          </p>
          <button
            class="px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-12 bg-n-solid-3 hover:bg-n-solid-3"
            @click="runSimulation"
          >
            {{ t('AUTOMATION.CANVAS.SIMULATE.RETRY') }}
          </button>
        </div>

        <!-- Fluxo vazio -->
        <div
          v-else-if="!steps.length"
          class="flex flex-col items-center gap-2 py-10 text-center text-n-slate-10"
        >
          <span class="text-2xl i-lucide-workflow" />
          <p class="text-sm">
            {{ t('AUTOMATION.CANVAS.SIMULATE.EMPTY') }}
          </p>
        </div>

        <!-- Passos percorridos (o caminho tomado) -->
        <ol v-else class="flex flex-col gap-0">
          <li
            v-for="(step, index) in steps"
            :key="`${step.node_id}-${index}`"
            class="relative flex gap-3 pb-4 last:pb-0"
            data-testid="simulation-step"
          >
            <!-- Trilho vertical ligando os passos -->
            <span
              v-if="index < steps.length - 1"
              class="absolute left-[15px] top-8 bottom-0 w-px bg-n-weak"
            />
            <span
              class="z-10 grid rounded-full size-8 shrink-0 place-items-center bg-n-alpha-1"
              :style="{ color: stepMeta(step).color }"
            >
              <span :class="stepMeta(step).icon" />
            </span>
            <div
              class="flex flex-col flex-1 min-w-0 gap-1 p-3 border rounded-lg border-n-weak bg-n-solid-2"
            >
              <div class="flex items-center gap-2">
                <span
                  class="text-[10px] font-bold text-n-slate-10 tabular-nums"
                >
                  {{ index + 1 }}
                </span>
                <span class="text-sm font-semibold truncate text-n-slate-12">
                  {{ stepMeta(step).label }}
                </span>
                <span
                  v-if="branchInfo(step)"
                  class="ml-auto shrink-0 px-1.5 py-0.5 rounded text-[11px] font-semibold"
                  :class="TONE_CLASSES[branchInfo(step).tone]"
                >
                  {{ branchInfo(step).label }}
                </span>
              </div>
              <p class="text-xs leading-snug text-n-slate-11">
                {{ step.would }}
              </p>
            </div>
          </li>
        </ol>
      </div>

      <footer
        class="flex items-center gap-2 px-4 border-t h-14 shrink-0 border-n-weak"
      >
        <span v-if="!isLoading && !errorKind" class="text-xs text-n-slate-11">
          {{
            t('AUTOMATION.CANVAS.SIMULATE.STEP_COUNT', { count: steps.length })
          }}
        </span>
        <button
          class="ml-auto px-3 py-1.5 text-xs font-medium rounded-lg text-n-slate-12 bg-n-solid-3 hover:bg-n-solid-3 disabled:opacity-60"
          :disabled="isLoading"
          data-testid="simulation-rerun"
          @click="runSimulation"
        >
          {{ t('AUTOMATION.CANVAS.SIMULATE.RERUN') }}
        </button>
      </footer>
    </aside>
  </div>
</template>
