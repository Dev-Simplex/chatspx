<script setup>
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
  watch,
} from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { VueFlow, MarkerType } from '@vue-flow/core';
import { Background } from '@vue-flow/background';
import { Controls } from '@vue-flow/controls';
import { MiniMap } from '@vue-flow/minimap';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import FlowNode from './FlowNode.vue';
import FlowEdge from './FlowEdge.vue';
import ConfigPanel from './ConfigPanel.vue';
import SimulationOverlay from './SimulationOverlay.vue';
import LogsPanel from './LogsPanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  NODE_CATALOG,
  FAMILIES,
  PALETTE_SECTIONS,
  familyForNode,
} from './nodeCatalog';
import { flatToDefinition } from './flatToDefinition';
import { flowTemplateByKey } from './flowTemplates';
import { computeTreeLayout, H_SPACING, V_SPACING } from './flowLayout';
import { useFlowHistory } from './useFlowHistory';

import '@vue-flow/core/dist/style.css';
import '@vue-flow/core/dist/theme-default.css';
import '@vue-flow/controls/dist/style.css';
import '@vue-flow/minimap/dist/style.css';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const flowId = computed(() => route.params.flowId);
const isEdit = computed(() => Boolean(flowId.value));

// Paleta de blocos: agrupada por seção (PALETTE_SECTIONS) + busca. `paletteQuery` filtra os itens
// pelo rótulo resolvido via t() (sem caixa nem acento — normalizeSearch tira os diacríticos).
// `paletteSections` percorre as seções na ordem do design system, agrupa o NODE_CATALOG pela
// `family` de cada item e descarta seções sem resultado; `hasPaletteResults` distingue o estado
// "nenhum bloco" (busca sem correspondência).
const paletteQuery = ref('');
const normalizeSearch = value =>
  (value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
const paletteSections = computed(() => {
  const query = normalizeSearch(paletteQuery.value.trim());
  return PALETTE_SECTIONS.map(section => ({
    ...section,
    items: NODE_CATALOG.filter(
      item =>
        item.family === section.family &&
        (!query || normalizeSearch(t(item.labelKey)).includes(query))
    ),
  })).filter(section => section.items.length);
});
const hasPaletteResults = computed(() => paletteSections.value.length > 0);

const name = ref('');
const definition = ref({ nodes: [], edges: [] });
const isSaving = ref(false);
// Falha ao carregar um fluxo existente (404/erro): mostra um estado de erro em vez de um canvas
// vazio (que ao salvar sobrescreveria o registro). Não redirecionamos no onMounted — navegar
// durante a montagem inicial do app trava a montagem; o usuário volta pela ação do estado.
const loadError = ref(false);
const selectedNodeId = ref(null);
const flowInstance = ref(null);

// Tema atual: o app alterna a classe `.dark` no <body> (themeHelper.js). Observamos a classe
// para repintar o MiniMap no dark (o Vue Flow o desenha claro por padrão) e escolher a
// variante de cor dos nós no minimapa. Um MutationObserver cobre qualquer origem da troca
// (toggle manual do usuário ou mudança do SO no modo automático).
const isDark = ref(false);
let themeObserver = null;
const syncTheme = () => {
  isDark.value =
    typeof document !== 'undefined' && document.body.classList.contains('dark');
};
// Overlays de simulação (dry-run) e de execuções/logs — só fazem sentido num fluxo já salvo
// (precisam do id pra bater no backend), por isso os botões aparecem só quando isEdit.
const showSimulation = ref(false);
const showLogs = ref(false);

// Analytics por nó (Fase 3.3): map node_id → { executions, failures, pct } carregado do backend
// (flows/getStats) ao abrir um flow SALVO. Alimenta as pills "142 · 38%" do FlowNode. Fica {} num
// flow novo (sem id, nada a mostrar) — a ausência de stat é o estado padrão da pill.
const nodeStats = ref({});

// Histórico undo/redo da definition. `suppressHistory` blinda o watcher enquanto aplicamos um
// snapshot (undo/redo) ou o echo read-only do webhook_token — mutações que NÃO são edições do
// usuário e não devem virar passos de undo nem marcar o fluxo como sujo.
const history = useFlowHistory();
const { canUndo, canRedo, isDirty } = history;
const suppressHistory = ref(false);

const nodeTypes = { flow: FlowNode };
const edgeTypes = { flow: FlowEdge };

// Roda uma mutação da definition sem registrá-la no histórico (o watcher é assíncrono; o flag
// segue ligado durante o flush e só é liberado no próximo tick).
const withoutHistory = fn => {
  suppressHistory.value = true;
  fn();
  nextTick(() => {
    suppressHistory.value = false;
  });
};

// Fonte única de captura: toda mutação da definition (todas imutáveis nos handlers) alimenta o
// histórico por aqui — debounced dentro do composable. Pulado sob suppressHistory.
watch(
  definition,
  value => {
    if (suppressHistory.value) return;
    history.record(value);
  },
  { deep: true }
);

const applySnapshot = snapshot => {
  if (!snapshot) return;
  withoutHistory(() => {
    definition.value = snapshot;
    // Se o nó selecionado sumiu no snapshot, fecha o painel de configuração.
    const stillExists = (snapshot.nodes || []).some(
      node => String(node.id) === String(selectedNodeId.value)
    );
    if (selectedNodeId.value && !stillExists) selectedNodeId.value = null;
  });
};

const undo = () => applySnapshot(history.undo());
const redo = () => applySnapshot(history.redo());

// Não sequestrar o undo nativo enquanto o usuário digita num campo do painel de configuração.
const isEditableTarget = target => {
  if (!target) return false;
  if (target.isContentEditable) return true;
  const tag = target.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
};

const goBack = () =>
  router.push({ name: 'automation_list', params: route.params });

// Guarda contra perda de trabalho: confirma antes de sair (navegação via router ou fechar/
// recarregar a aba) com alterações não salvas. isDirty só fica true após uma edição real.
const onBeforeUnload = event => {
  if (!isDirty.value) return;
  event.preventDefault();
  event.returnValue = '';
};

// Ctrl/Cmd+Z = desfazer; Ctrl/Cmd+Shift+Z ou Ctrl+Y = refazer.
const onKeydown = event => {
  if (!(event.ctrlKey || event.metaKey)) return;
  const key = event.key.toLowerCase();
  const wantsRedo = (key === 'z' && event.shiftKey) || key === 'y';
  const wantsUndo = key === 'z' && !event.shiftKey;
  if (!wantsRedo && !wantsUndo) return;
  if (isEditableTarget(event.target)) return;
  event.preventDefault();
  if (wantsRedo) redo();
  else undo();
};

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown);
  window.removeEventListener('beforeunload', onBeforeUnload);
  themeObserver?.disconnect();
});

// Cores dos ramos fixos (espelham FlowNode/FlowEdge). Rotas do router herdam a cor da família.
const BRANCH_TRUE_COLOR = '#0e9f6e';
const BRANCH_FALSE_COLOR = '#e5484d';
const BRANCH_FALLBACK_COLOR = '#8b93aa';

// Identidade do ramo: normaliza null/undefined/'' — uma porta de saída sem branch é o fluxo
// linear (Handle padrão). Usada para casar/deduplicar arestas por (origem, ramo).
const branchId = branch => (branch == null ? '' : String(branch));

// Id ESTÁVEL da aresta (inclui o ramo): duas arestas podem sair do mesmo nó por ramos
// diferentes. É o id que o Vue Flow usa e o que o onEdgesChange casa ao remover.
const edgeKey = edge => `${edge.from}:${branchId(edge.branch)}->${edge.to}`;

// Portas de saída válidas de um nó (para podar arestas órfãs quando uma rota é apagada).
const validBranchKeys = node => {
  if (node.type === 'condition') return ['true', 'false'];
  if (node.type === 'router') {
    const keys = (Array.isArray(node.routes) ? node.routes : []).map(r =>
      String(r.key)
    );
    keys.push(String(node.fallback_key || 'fallback'));
    return keys;
  }
  return [];
};

// Rótulo + cor do pill da aresta, derivados do nó de origem: 'true'→Sim, 'false'→Não, key da
// rota→nome da rota (ou "Rota N"), fallback_key→"Senão". Sem ramo → sem rótulo (linear).
const branchMeta = edge => {
  const branch = edge.branch;
  if (branch == null) return { label: '', color: null };
  const from = (definition.value.nodes || []).find(
    n => String(n.id) === String(edge.from)
  );
  if (from?.type === 'condition') {
    if (String(branch) === 'true')
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.YES'),
        color: BRANCH_TRUE_COLOR,
      };
    if (String(branch) === 'false')
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.NO'),
        color: BRANCH_FALSE_COLOR,
      };
  }
  if (from?.type === 'router') {
    if (String(branch) === String(from.fallback_key || 'fallback')) {
      return {
        label: t('AUTOMATION.CANVAS.CONFIG.ROUTER.FALLBACK'),
        color: BRANCH_FALLBACK_COLOR,
      };
    }
    const routes = Array.isArray(from.routes) ? from.routes : [];
    const idx = routes.findIndex(r => String(r.key) === String(branch));
    if (idx >= 0) {
      return {
        label:
          routes[idx].label ||
          t('AUTOMATION.CANVAS.CONFIG.ROUTER.ROUTE_N', { n: idx + 1 }),
        color: null,
      };
    }
  }
  return { label: String(branch), color: null };
};

const selectedNode = computed(
  () =>
    (definition.value.nodes || []).find(
      node => String(node.id) === String(selectedNodeId.value)
    ) || null
);

// Uma posição é "manual" quando o usuário a arrastou (persistida em definition.node.position).
// Essas são RESPEITADAS; os demais nós recebem a posição derivada do auto-layout em árvore.
const hasPosition = node =>
  node.position &&
  Number.isFinite(node.position.x) &&
  Number.isFinite(node.position.y);

// Auto-layout em árvore DERIVADO da definition (fonte da verdade): filhos abaixo do pai, ramos
// (Sim/Não, rotas) em colunas lado a lado. Computed próprio para o algoritmo O(n+e) só rodar em
// mudança ESTRUTURAL — não a cada clique de seleção nem atualização de stats (que passam por vfNodes).
const nodeLayout = computed(() => computeTreeLayout(definition.value));

const vfNodes = computed(() => {
  const layout = nodeLayout.value;
  return (definition.value.nodes || []).map(node => ({
    id: String(node.id),
    type: 'flow',
    position: hasPosition(node)
      ? node.position
      : layout.get(String(node.id)) || { x: 0, y: 0 },
    selected: String(node.id) === String(selectedNodeId.value),
    data: { node, stats: nodeStats.value[String(node.id)] || null },
  }));
});
// Aresta → Vue Flow: `sourceHandle` = branch (casa o Handle rotulado do FlowNode); `type:flow`
// desenha o FlowEdge com o pill do ramo. Arestas sem branch saem do Handle padrão (linear).
const vfEdges = computed(() =>
  (definition.value.edges || [])
    .filter(edge => edge.to)
    .map(edge => ({
      id: edgeKey(edge),
      source: String(edge.from),
      target: String(edge.to),
      sourceHandle: edge.branch != null ? String(edge.branch) : undefined,
      type: 'flow',
      markerEnd: MarkerType.ArrowClosed,
      data: branchMeta(edge),
    }))
);

// Cor do nó no MiniMap, por família. No dark usa a variante `colorDark` (mais clara/saturada)
// para manter contraste sobre o fundo escuro do minimapa.
const nodeColor = node => {
  const raw = node.data?.node || {};
  const family = FAMILIES[familyForNode(raw)] || FAMILIES.action;
  return isDark.value ? family.colorDark || family.color : family.color;
};

// Opções usadas pelos editores de nó (agente/time/etiqueta/inbox/atributos/IA).
const loadConfigOptions = () => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('attributes/get');
  store.dispatch('captainAssistants/get').catch(() => {});
};

// O webhook_token é backend-autoritativo e vive em flow.trigger_config; injetamo-lo no nó
// `trigger` (in-memory) para o TriggerConfig exibir a URL read-only. É só um ECHO de exibição —
// o backend ignora qualquer token vindo no payload (Flow#ensure_webhook_token).
const syncWebhookToken = flow => {
  const token = flow?.trigger_config?.webhook_token;
  if (!token) return;
  definition.value = {
    ...definition.value,
    nodes: (definition.value.nodes || []).map(node =>
      node.type === 'trigger' ? { ...node, webhook_token: token } : node
    ),
  };
};

// Abre uma AutomationRule clássica no canvas (rota `new` com ?fromRuleId=<id>): converte a regra
// (event_name + conditions + actions) numa `definition` via flatToDefinition — inteiramente
// client-side, sem depender do backfill do servidor. O usuário revisa e salva como um Flow novo.
const seedFromRule = async ruleId => {
  const findRule = () =>
    (store.getters['automations/getAutomations'] || []).find(
      rule => String(rule.id) === String(ruleId)
    );
  let rule = findRule();
  if (!rule) {
    await store.dispatch('automations/get');
    rule = findRule();
  }
  if (!rule) return false;
  name.value = rule.name || t('AUTOMATION.CANVAS.NEW_FLOW');
  definition.value = flatToDefinition(rule);
  return true;
};

// Abre um MODELO da galeria no canvas (rota `new` com ?templateKey=<key>): copia a definition
// pronta do flowTemplates para o canvas — deep-clone para NUNCA mutar o módulo compartilhado — e
// nomeia o fluxo com o nome (editável) do modelo. NADA é gravado até o usuário salvar; o nó
// `trigger` já carrega event_name/trigger_kind, então triggerPayload deriva o trigger_type no
// save (não precisamos do trigger_type declarado no template aqui). Espelha o seedFromRule.
const seedFromTemplate = key => {
  const template = flowTemplateByKey(key);
  if (!template) return false;
  name.value = t(template.nameKey);
  definition.value = structuredClone(template.definition);
  return true;
};

// Carrega o analytics por nó do flow salvo e o expõe em nodeStats (node_id → stat). Best-effort:
// as pills são um extra — se o endpoint falhar, o canvas segue sem elas (nunca quebra a edição).
const loadStats = async () => {
  if (!isEdit.value) return;
  try {
    const data = await store.dispatch('flows/getStats', { id: flowId.value });
    nodeStats.value = data?.nodes || {};
  } catch (error) {
    nodeStats.value = {};
  }
};

onMounted(async () => {
  window.addEventListener('keydown', onKeydown);
  window.addEventListener('beforeunload', onBeforeUnload);
  syncTheme();
  themeObserver = new MutationObserver(syncTheme);
  themeObserver.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
  loadConfigOptions();

  if (!isEdit.value) {
    let seeded = false;
    if (route.query.fromRuleId) {
      seeded = await seedFromRule(route.query.fromRuleId);
    } else if (route.query.templateKey) {
      seeded = seedFromTemplate(route.query.templateKey);
    }
    if (!seeded) name.value = t('AUTOMATION.CANVAS.NEW_FLOW');
    history.commit(definition.value);
    return;
  }

  let flow = store.getters['flows/getFlow'](flowId.value);
  if (!flow) {
    try {
      flow = await store.dispatch('flows/show', flowId.value);
    } catch (error) {
      loadError.value = true;
      return;
    }
  }
  // Fluxo inexistente/sem retorno: marca erro e mostra um estado claro em vez de um canvas vazio
  // "editável" que sobrescreveria o registro real ao salvar (evita perda de dados).
  if (!flow) {
    loadError.value = true;
    return;
  }
  name.value = flow.name;
  definition.value = flow.definition || { nodes: [], edges: [] };
  withoutHistory(() => syncWebhookToken(flow));
  history.commit(definition.value);
  loadStats();
});

// Gera um id de nó garantidamente único no grafo, robusto a ids sem dígito (ex.: importados de
// fluxos legados como "trigger") — que no esquema antigo colapsariam em 0 e colidiriam entre si.
const nextNodeId = () => {
  const taken = new Set((definition.value.nodes || []).map(n => String(n.id)));
  let i = taken.size + 1;
  while (taken.has(`n${i}`)) i += 1;
  return `n${i}`;
};

// Posição do nó novo, coerente com a árvore. Retornar `undefined` = SEM position → o nó entra
// no auto-layout (flowLayout) e é posicionado como filho do pai. Só fixamos uma posição quando
// há nós MANUAIS por perto (ex.: um template com posições curadas), para o novo nó pousar junto
// deles em vez de saltar para a origem do auto-layout:
//  • auto-ligado (linear) a um `prev` manual → logo abaixo do prev, na mesma coluna;
//  • auto-ligado a um `prev` auto-posicionado → undefined (o auto-layout o coloca sob o pai);
//  • solto, mas há nós manuais → coluna à direita do mais baixo, sem sobrepor;
//  • solto e tudo é auto → undefined (o auto-layout trata como nova raiz).
const positionForNewNode = (prev, autoConnected, existing) => {
  if (autoConnected && prev && hasPosition(prev)) {
    return { x: prev.position.x, y: prev.position.y + V_SPACING };
  }
  if (autoConnected) return undefined;
  const positioned = existing.filter(hasPosition);
  if (!positioned.length) return undefined;
  const lowest = positioned.reduce((a, b) =>
    b.position.y > a.position.y ? b : a
  );
  return { x: lowest.position.x + H_SPACING, y: lowest.position.y };
};

const addNode = item => {
  const id = nextNodeId();
  const existing = definition.value.nodes || [];
  const edges = [...(definition.value.edges || [])];

  // Auto-liga só o caso linear seguro: o nó anterior é de saída única (não condition/router) e
  // ainda não tem aresta de saída. Ramos são sempre conectados manualmente pelo usuário.
  const prev = existing[existing.length - 1];
  const prevIsBranch = prev && ['condition', 'router'].includes(prev.type);
  const prevHasOutgoing =
    prev && edges.some(e => String(e.from) === String(prev.id));
  const autoConnected = Boolean(prev && !prevIsBranch && !prevHasOutgoing);

  const node = { id, type: item.type };
  const position = positionForNewNode(prev, autoConnected, existing);
  if (position) node.position = position;
  if (item.actionName) {
    node.action_name = item.actionName;
    node.action_params = [];
  }
  // Router nasce com uma rota vazia + fallback, para já expor as portas de saída no canvas.
  if (item.type === 'router') {
    node.routes = [{ key: 'route_1', label: '', conditions: [] }];
    node.fallback_key = 'fallback';
  }
  if (autoConnected) edges.push({ from: prev.id, to: id });

  definition.value = { nodes: [...existing, node], edges };
  selectedNodeId.value = id;
  // Re-enquadra para o nó novo entrar na área visível (fit-view-on-init só roda na montagem).
  nextTick(() => flowInstance.value?.fitView({ padding: 0.3, duration: 300 }));
};

const onFlowInit = instance => {
  flowInstance.value = instance;
};

// Conexão manual: o usuário arrastou de um Handle de origem para o alvo. `sourceHandle` é o
// branch (id do Handle) — para condition/router; ausente = fluxo linear. UMA aresta por porta
// de saída: reconectar a mesma porta SUBSTITUI a aresta anterior daquele ramo (imutável).
const onConnect = connection => {
  const { source, target, sourceHandle } = connection;
  if (!source || !target) return;
  const branch = sourceHandle || undefined;
  const edges = (definition.value.edges || []).filter(
    edge =>
      !(
        String(edge.from) === String(source) &&
        branchId(edge.branch) === branchId(branch)
      )
  );
  const edge = { from: source, to: target };
  if (branch) edge.branch = branch;
  definition.value = { ...definition.value, edges: [...edges, edge] };
};

// Remoção de arestas (tecla Delete ou o × do FlowEdge → removeEdges → edges-change). Sincroniza
// a exclusão de volta na definition (fonte da verdade), casando pelo id estável.
const onEdgesChange = changes => {
  const removed = new Set(
    changes.filter(change => change.type === 'remove').map(change => change.id)
  );
  if (!removed.size) return;
  definition.value = {
    ...definition.value,
    edges: (definition.value.edges || []).filter(
      edge => !removed.has(edgeKey(edge))
    ),
  };
};

// Remoção de NÓS (tecla Delete/Backspace com nó selecionado, ou botão excluir do painel). Tira o
// nó da definition E poda toda aresta conectada a ele (entrada e saída), sem deixar aresta órfã.
// Espelha onEdgesChange: a definition é a fonte da verdade; o Vue Flow só emite a intenção.
const removeNodeIds = ids => {
  const gone = new Set(ids.map(String));
  if (!gone.size) return;
  definition.value = {
    ...definition.value,
    nodes: (definition.value.nodes || []).filter(
      node => !gone.has(String(node.id))
    ),
    edges: (definition.value.edges || []).filter(
      edge => !gone.has(String(edge.from)) && !gone.has(String(edge.to))
    ),
  };
  if (gone.has(String(selectedNodeId.value))) selectedNodeId.value = null;
};

const onNodesChange = changes =>
  removeNodeIds(
    changes.filter(change => change.type === 'remove').map(change => change.id)
  );

const removeSelectedNode = () => {
  if (selectedNodeId.value != null) removeNodeIds([selectedNodeId.value]);
};

// Persiste a(s) posição(ões) após arrastar — assim o layout do usuário sobrevive ao reload.
const onNodeDragStop = ({ nodes: dragged }) => {
  if (!dragged?.length) return;
  const moved = new Map(
    dragged.map(n => [
      String(n.id),
      { x: Math.round(n.position.x), y: Math.round(n.position.y) },
    ])
  );
  definition.value = {
    ...definition.value,
    nodes: (definition.value.nodes || []).map(node =>
      moved.has(String(node.id))
        ? { ...node, position: moved.get(String(node.id)) }
        : node
    ),
  };
};

const onNodeClick = ({ node }) => {
  selectedNodeId.value = node?.id ?? null;
};

const onPaneClick = () => {
  selectedNodeId.value = null;
};

// Aplica um patch ao nó selecionado de forma IMUTÁVEL (substitui o nó no array), como a
// definition espera. O patch vem do editor: action_params, conditions, event_name, routes…
// Ao mudar as portas de um nó (ex.: apagar uma rota do router), poda as arestas cujo `branch`
// não corresponde mais a uma porta válida daquele nó — evita arestas órfãs no grafo.
const updateSelectedNode = patch => {
  if (!selectedNodeId.value) return;
  const nodes = (definition.value.nodes || []).map(node =>
    String(node.id) === String(selectedNodeId.value)
      ? { ...node, ...patch }
      : node
  );
  const byId = new Map(nodes.map(node => [String(node.id), node]));
  const edges = (definition.value.edges || []).filter(edge => {
    if (edge.branch == null) return true;
    const from = byId.get(String(edge.from));
    return !from || validBranchKeys(from).includes(String(edge.branch));
  });
  definition.value = { ...definition.value, nodes, edges };
};

// Projeta o nó `trigger` em { trigger_type, trigger_config } para o backend. A fonte da
// verdade continua sendo o nó na definition (round-trip pelo canvas); aqui só derivamos o
// que o motor consome. Sem nó de gatilho o flow é `manual`.
//  • trigger_kind 'keyword'  → trigger_type keyword  + { keywords[], match }
//  • trigger_kind 'schedule' → trigger_type schedule + { mode, cron | every, unit }
//  • trigger_kind 'webhook'  → trigger_type external_webhook + {} (o backend gera/preserva o
//    webhook_token — nunca o cliente; ver Flow#ensure_webhook_token)
//  • event_name definido      → trigger_type conversation_event + { event_name }
const triggerPayload = triggerNode => {
  if (!triggerNode) return { trigger_type: 'manual', trigger_config: {} };
  if (triggerNode.trigger_kind === 'webhook') {
    return { trigger_type: 'external_webhook', trigger_config: {} };
  }
  if (triggerNode.trigger_kind === 'keyword') {
    return {
      trigger_type: 'keyword',
      trigger_config: {
        keywords: (triggerNode.keywords || [])
          .map(kw => (kw || '').trim())
          .filter(Boolean),
        match: triggerNode.match === 'exact' ? 'exact' : 'contains',
        direction: triggerNode.direction || 'both',
      },
    };
  }
  if (triggerNode.trigger_kind === 'schedule') {
    const sched = triggerNode.schedule || {};
    if (sched.mode === 'interval') {
      const every = Number.parseInt(sched.every, 10);
      return {
        trigger_type: 'schedule',
        trigger_config: {
          mode: 'interval',
          every: Number.isNaN(every) || every < 1 ? 1 : every,
          unit: ['minutes', 'hours', 'days'].includes(sched.unit)
            ? sched.unit
            : 'days',
        },
      };
    }
    return {
      trigger_type: 'schedule',
      trigger_config: { mode: 'cron', cron: String(sched.cron ?? '').trim() },
    };
  }
  if (triggerNode.event_name) {
    return {
      trigger_type: 'conversation_event',
      trigger_config: {
        event_name: triggerNode.event_name,
        direction: triggerNode.direction || 'both',
      },
    };
  }
  return { trigger_type: 'manual', trigger_config: {} };
};

// Validação mínima antes de persistir: nome, ao menos um gatilho e uma ação. Evita criar um
// fluxo vazio/inutilizável (o backend aceitaria, mas ele não faria nada).
const validationError = () => {
  const nodes = definition.value.nodes || [];
  if (!name.value.trim())
    return t('AUTOMATION.CANVAS.VALIDATION.NAME_REQUIRED');
  if (!nodes.some(node => node.type === 'trigger'))
    return t('AUTOMATION.CANVAS.VALIDATION.TRIGGER_REQUIRED');
  if (!nodes.some(node => node.type !== 'trigger'))
    return t('AUTOMATION.CANVAS.VALIDATION.ACTION_REQUIRED');
  return null;
};

const save = async () => {
  if (isSaving.value) return;
  const invalid = validationError();
  if (invalid) {
    useAlert(invalid);
    return;
  }
  isSaving.value = true;
  try {
    const triggerNode = (definition.value.nodes || []).find(
      n => n.type === 'trigger'
    );
    const payload = {
      name: name.value,
      definition: definition.value,
      ...triggerPayload(triggerNode),
    };
    if (isEdit.value) {
      const updated = await store.dispatch('flows/update', {
        id: flowId.value,
        ...payload,
      });
      withoutHistory(() => syncWebhookToken(updated));
      history.markSaved(definition.value);
      useAlert(t('AUTOMATION.CANVAS.SAVED'));
    } else {
      const created = await store.dispatch('flows/create', payload);
      withoutHistory(() => syncWebhookToken(created));
      history.markSaved(definition.value);
      useAlert(t('AUTOMATION.CANVAS.CREATED'));
      router.replace({
        name: 'automation_canvas_edit',
        params: { ...route.params, flowId: created.id },
      });
    }
  } catch (error) {
    useAlert(t('AUTOMATION.CANVAS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onBeforeRouteLeave(
  () =>
    !isDirty.value ||
    // eslint-disable-next-line no-alert
    window.confirm(t('AUTOMATION.CANVAS.UNSAVED_CONFIRM'))
);
</script>

<template>
  <div
    class="relative flex flex-col w-full h-full bg-n-solid-2"
    data-testid="flow-canvas-view"
  >
    <div
      v-if="loadError"
      class="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 text-center bg-n-solid-2"
      data-testid="canvas-load-error"
    >
      <span class="text-4xl i-lucide-triangle-alert text-n-amber-9" />
      <p class="text-sm text-n-slate-11">
        {{ t('AUTOMATION.CANVAS.LOAD_ERROR') }}
      </p>
      <Button
        :label="t('AUTOMATION.CANVAS.BACK')"
        data-testid="canvas-load-error-back"
        @click="goBack"
      />
    </div>
    <header
      class="flex items-center gap-3 px-4 border-b h-14 shrink-0 border-n-weak bg-n-solid-1"
    >
      <button
        class="text-n-slate-11 hover:text-n-slate-12"
        :aria-label="t('AUTOMATION.CANVAS.BACK')"
        :title="t('AUTOMATION.CANVAS.BACK')"
        data-testid="canvas-back"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left" />
      </button>
      <input
        v-model="name"
        class="flex-1 max-w-md px-2 py-1 text-sm font-semibold bg-transparent rounded outline-none reset-base text-n-slate-12 focus:bg-n-solid-2"
        :placeholder="t('AUTOMATION.CANVAS.NAME_PLACEHOLDER')"
        data-testid="canvas-name"
      />
      <span
        v-if="isDirty"
        class="rounded-full size-1.5 shrink-0 bg-n-amber-9"
        :aria-label="t('AUTOMATION.CANVAS.UNSAVED')"
        :title="t('AUTOMATION.CANVAS.UNSAVED')"
        data-testid="canvas-dirty"
      />
      <div class="flex items-center gap-0.5">
        <button
          class="grid rounded-lg size-8 place-items-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:hover:bg-transparent disabled:hover:text-n-slate-11"
          :disabled="!canUndo"
          :aria-label="t('AUTOMATION.CANVAS.UNDO')"
          :title="t('AUTOMATION.CANVAS.UNDO')"
          data-testid="canvas-undo"
          @click="undo"
        >
          <span class="i-lucide-undo-2" />
        </button>
        <button
          class="grid rounded-lg size-8 place-items-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:hover:bg-transparent disabled:hover:text-n-slate-11"
          :disabled="!canRedo"
          :aria-label="t('AUTOMATION.CANVAS.REDO')"
          :title="t('AUTOMATION.CANVAS.REDO')"
          data-testid="canvas-redo"
          @click="redo"
        >
          <span class="i-lucide-redo-2" />
        </button>
      </div>
      <button
        v-if="isEdit"
        class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
        data-testid="canvas-logs"
        @click="showLogs = true"
      >
        <span class="i-lucide-scroll-text" />
        {{ t('AUTOMATION.CANVAS.LOGS.OPEN') }}
      </button>
      <button
        v-if="isEdit"
        class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
        data-testid="canvas-simulate"
        @click="showSimulation = true"
      >
        <span class="i-lucide-flask-conical" />
        {{ t('AUTOMATION.CANVAS.SIMULATE.OPEN') }}
      </button>
      <Button
        :label="t('AUTOMATION.CANVAS.SAVE')"
        :is-loading="isSaving"
        :disabled="isSaving"
        data-testid="canvas-save"
        @click="save"
      />
    </header>

    <div class="flex flex-1 min-h-0">
      <aside
        class="flex flex-col w-56 gap-1 p-2 overflow-y-auto border-r shrink-0 border-n-weak bg-n-solid-1"
      >
        <span
          class="px-2 py-1 text-[10px] font-bold tracking-wider uppercase text-n-slate-10"
        >
          {{ t('AUTOMATION.CANVAS.PALETTE') }}
        </span>
        <div
          class="flex items-center h-8 gap-2 px-2 mb-1 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak dark:outline-n-strong focus-within:outline-n-brand"
        >
          <span class="text-sm shrink-0 text-n-slate-10 i-lucide-search" />
          <input
            v-model="paletteQuery"
            type="text"
            class="w-full h-full p-0 text-sm bg-transparent border-0 outline-none reset-base text-n-slate-12"
            :placeholder="t('AUTOMATION.CANVAS.PALETTE_SEARCH')"
            data-testid="palette-search"
          />
        </div>
        <template v-for="section in paletteSections" :key="section.family">
          <span
            class="px-2 pt-2 pb-0.5 text-[10px] font-bold tracking-wider uppercase text-n-slate-10"
          >
            {{ t(section.labelKey) }}
          </span>
          <button
            v-for="item in section.items"
            :key="item.key"
            class="flex items-center gap-2 px-2 py-1.5 text-sm text-left rounded-lg text-n-slate-12 hover:bg-n-solid-3"
            :data-testid="`palette-${item.key}`"
            @click="addNode(item)"
          >
            <span
              class="w-2 h-2 rounded-full shrink-0"
              :style="{
                backgroundColor: (FAMILIES[item.family] || FAMILIES.action)
                  .color,
              }"
            />
            {{ t(item.labelKey) }}
          </button>
        </template>
        <p
          v-if="!hasPaletteResults"
          class="px-2 py-3 text-sm text-center text-n-slate-10"
          data-testid="palette-empty"
        >
          {{ t('AUTOMATION.CANVAS.PALETTE_NO_RESULTS') }}
        </p>
      </aside>

      <main class="relative flex-1 min-w-0">
        <VueFlow
          :nodes="vfNodes"
          :edges="vfEdges"
          :node-types="nodeTypes"
          :edge-types="edgeTypes"
          :default-viewport="{ zoom: 0.9 }"
          :delete-key-code="['Delete', 'Backspace']"
          default-marker-color="#8b93aa"
          fit-view-on-init
          class="w-full h-full"
          @node-click="onNodeClick"
          @pane-click="onPaneClick"
          @init="onFlowInit"
          @connect="onConnect"
          @edges-change="onEdgesChange"
          @nodes-change="onNodesChange"
          @node-drag-stop="onNodeDragStop"
        >
          <template #node-flow="nodeProps">
            <FlowNode v-bind="nodeProps" />
          </template>
          <template #edge-flow="edgeProps">
            <FlowEdge v-bind="edgeProps" />
          </template>
          <Background :gap="16" />
          <Controls />
          <MiniMap
            :node-color="nodeColor"
            :mask-color="
              isDark ? 'rgba(12, 14, 18, 0.6)' : 'rgba(240, 240, 240, 0.6)'
            "
            pannable
            zoomable
          />
        </VueFlow>

        <div
          v-if="!vfNodes.length"
          class="absolute inset-0 flex flex-col items-center justify-center gap-2 pointer-events-none text-n-slate-10"
          data-testid="canvas-empty"
        >
          <span class="text-3xl i-lucide-workflow" />
          <p class="text-sm">{{ t('AUTOMATION.CANVAS.EMPTY') }}</p>
        </div>
      </main>

      <ConfigPanel
        v-if="selectedNode"
        :node="selectedNode"
        @close="onPaneClick"
        @update="updateSelectedNode"
        @delete="removeSelectedNode"
      />
    </div>

    <SimulationOverlay
      v-if="showSimulation"
      :flow-id="flowId"
      :definition="definition"
      @close="showSimulation = false"
    />
    <LogsPanel v-if="showLogs" :flow-id="flowId" @close="showLogs = false" />
  </div>
</template>

<style>
/* Widgets do Vue Flow (MiniMap + Controls) nascem claros e ficam "brancos" no dark. Repintamos
   para o tema escuro do app. Global (não scoped) porque essas classes são do Vue Flow e só
   existem no canvas; o prefixo `.dark` — que o app põe no <body> (themeHelper.js) — as isola do
   tema claro, que segue com o default do Vue Flow. A cor dos NÓS e a máscara do MiniMap vão por
   prop reativa (:node-color/:mask-color); aqui tratamos só o que não tem API de prop: o fundo. */
.dark .vue-flow__minimap {
  background-color: #1b1d23;
}
.dark .vue-flow__controls {
  box-shadow: 0 0 2px 1px rgb(0 0 0 / 0.4);
}
.dark .vue-flow__controls-button {
  background: #22252c;
  border-bottom: 1px solid #33363d;
  fill: #cbd0d9;
}
.dark .vue-flow__controls-button:hover {
  background: #2c2f38;
}
</style>
