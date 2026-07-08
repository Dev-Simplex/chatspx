<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import { FAMILIES, familyForNode, labelForNode } from './nodeCatalog';

const props = defineProps({
  data: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
});

const { t } = useI18n();

const node = computed(() => props.data?.node || {});
const familyKey = computed(() => familyForNode(node.value));
const familyMeta = computed(() => FAMILIES[familyKey.value] || FAMILIES.action);
const familyLabel = computed(() => t(familyMeta.value.labelKey));
const label = computed(() => t(labelForNode(node.value)));
const subtitle = computed(() => {
  const params = node.value.action_params;
  if (Array.isArray(params) && params.length && typeof params[0] === 'string') {
    return params.join(', ');
  }
  return node.value.type === 'trigger' ? node.value.event_name || '' : '';
});
const isTrigger = computed(() => node.value.type === 'trigger');

// Analytics por nó (Fase 3.3): stat pré-agregado que o FlowCanvasView injeta em data.stats quando
// abre um flow salvo (via flows/getStats). Formato { executions, failures, pct }. Sem stat, ou nó
// que nunca rodou (executions 0), NÃO desenha pill — a ausência é o estado padrão. Números crus,
// sem i18n: a pill é "142 · 38%" (execuções · % das entradas que chegaram até aqui).
const stats = computed(() => props.data?.stats || null);
const hasStats = computed(
  () => Boolean(stats.value) && stats.value.executions > 0
);
const hasFailures = computed(() => hasStats.value && stats.value.failures > 0);
// Rótulo da pill montado no script (não texto cru no template) — "142 · 38%": execuções · % das
// entradas que chegaram até aqui. Números puros, sem i18n.
const statsLabel = computed(() =>
  hasStats.value ? `${stats.value.executions} · ${stats.value.pct}%` : ''
);
// Total cru para o tooltip (sem palavra: "142 · 38% · ✕3" quando há falha) — a pill em si mostra
// só "142 · 38%". Símbolos, não rótulos traduzidos, pra não tocar o automation.json.
const statsTitle = computed(() => {
  if (!hasStats.value) return undefined;
  return hasFailures.value
    ? `${statsLabel.value} · ✕${stats.value.failures}`
    : statsLabel.value;
});

// Portas de saída ROTULADAS dos nós de ramificação. Cada porta vira um `source` Handle cujo
// `id` é o `branch` que a aresta carrega (o Runner casa edge.branch === handle.id):
//  • condition → 2 portas fixas: 'true' (Sim) e 'false' (Não).
//  • router    → 1 porta por rota (id = route.key) na ORDEM + 1 porta de fallback.
// Renderizamos cada porta como uma linha `relative` com o Handle em Position.Right: o handle
// ancora no canto direito da própria linha, alinhando-se ao rótulo sem cálculo de offset.
// Nós de saída única (action/trigger/wait) não têm portas rotuladas: usam o Handle Bottom
// padrão (sem id → aresta sem `branch`, fluxo linear).
const TRUE_COLOR = '#0e9f6e';
const FALSE_COLOR = '#e5484d';
const FALLBACK_COLOR = '#8b93aa';

const branchPorts = computed(() => {
  const raw = node.value;
  if (raw.type === 'condition') {
    return [
      {
        key: 'true',
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.YES'),
        color: TRUE_COLOR,
      },
      {
        key: 'false',
        label: t('AUTOMATION.CANVAS.CONFIG.CONDITION.NO'),
        color: FALSE_COLOR,
      },
    ];
  }
  if (raw.type === 'router') {
    const routes = Array.isArray(raw.routes) ? raw.routes : [];
    const ports = routes.map((route, i) => ({
      key: String(route.key),
      label:
        route.label ||
        t('AUTOMATION.CANVAS.CONFIG.ROUTER.ROUTE_N', { n: i + 1 }),
      color: familyMeta.value.color,
    }));
    ports.push({
      key: String(raw.fallback_key || 'fallback'),
      label: t('AUTOMATION.CANVAS.CONFIG.ROUTER.FALLBACK'),
      color: FALLBACK_COLOR,
    });
    return ports;
  }
  return [];
});

const hasBranchPorts = computed(() => branchPorts.value.length > 0);
</script>

<template>
  <div
    class="relative flex items-stretch w-64 border rounded-xl bg-n-solid-1 border-n-weak shadow-sm transition-shadow"
    :class="selected ? 'ring-2 ring-offset-1 ring-offset-transparent' : ''"
    :style="selected ? { '--tw-ring-color': familyMeta.color } : {}"
    data-testid="flow-node"
  >
    <Handle
      v-if="!isTrigger"
      type="target"
      :position="Position.Top"
      :style="{ backgroundColor: familyMeta.color }"
    />
    <span
      class="w-1 shrink-0 rounded-l-[11px]"
      :style="{ backgroundColor: familyMeta.color }"
    />
    <div class="flex flex-col min-w-0 gap-0.5 px-3 py-2.5 grow">
      <div class="flex items-center justify-between gap-2">
        <span
          class="text-[10px] font-bold tracking-wider uppercase truncate"
          :style="{ color: familyMeta.color }"
        >
          {{ familyLabel }}
        </span>
        <span
          v-if="hasStats"
          class="inline-flex items-center shrink-0 rounded-full px-1.5 py-px text-[10px] font-semibold tabular-nums bg-n-alpha-2"
          :class="hasFailures ? 'text-n-ruby-11' : 'text-n-slate-11'"
          :title="statsTitle"
          data-testid="flow-node-stat"
        >
          {{ statsLabel }}
        </span>
      </div>
      <span class="text-sm font-semibold truncate text-n-slate-12">{{
        label
      }}</span>
      <span v-if="subtitle" class="text-xs truncate text-n-slate-11">{{
        subtitle
      }}</span>

      <ul
        v-if="hasBranchPorts"
        class="flex flex-col gap-1 p-0 m-0 mt-1.5 list-none"
        data-testid="flow-node-ports"
      >
        <li
          v-for="port in branchPorts"
          :key="port.key"
          class="relative flex items-center gap-1.5 pr-1.5 py-0.5 text-xs"
          :data-testid="`flow-node-port-${port.key}`"
        >
          <span
            class="rounded-full size-1.5 shrink-0"
            :style="{ backgroundColor: port.color }"
          />
          <span class="truncate text-n-slate-11">{{ port.label }}</span>
          <Handle
            :id="port.key"
            type="source"
            :position="Position.Right"
            :style="{ backgroundColor: port.color }"
          />
        </li>
      </ul>
    </div>
    <Handle
      v-if="!hasBranchPorts"
      type="source"
      :position="Position.Bottom"
      :style="{ backgroundColor: familyMeta.color }"
    />
  </div>
</template>
