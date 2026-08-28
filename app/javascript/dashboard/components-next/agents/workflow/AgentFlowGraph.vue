<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
// Editor de fluxo estilo n8n (bespoke, sem libs): canvas pan/zoom/fit, nós com
// handles de porta, arestas bézier animadas, grade que acompanha. Data-driven.
const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
  // Modelo da CONTA: `config.model` não existe no payload do assistant.
  model: { type: String, default: '' },
});
defineOptions({ name: 'AgentFlowGraph' });

const NODE_W = 188;
const NODE_H = 72;
const GAP = 72;
const BRANCH_DY = 78;

const behavior = computed(() => props.assistant?.behavior || {});
const config = computed(() => props.assistant?.config || {});
const isOn = key => {
  const v = behavior.value[key];
  if (!v) return false;
  if (typeof v === 'object') return v.enabled !== false;
  return Boolean(v);
};

const mainSteps = computed(() => {
  const bh = behavior.value;
  const cfg = config.value;
  const list = [
    {
      icon: 'i-lucide-message-square',
      color: '#0a84ff',
      title: 'Trigger',
      sub: 'WhatsApp',
    },
  ];
  if (isOn('router'))
    list.push({
      icon: 'i-lucide-filter',
      color: '#ff9500',
      title: 'Router',
      sub: 'Roteamento',
    });
  if (isOn('business_hours'))
    list.push({
      icon: 'i-lucide-clock',
      color: '#af52de',
      title: 'Business Hours',
      sub: bh.business_hours?.timezone || 'horário',
    });
  if (Number(bh.debounce_seconds) > 0)
    list.push({
      icon: 'i-lucide-timer',
      color: '#30b0c7',
      title: 'Debounce',
      sub: `${bh.debounce_seconds}s`,
    });
  if (isOn('media_pipeline'))
    list.push({
      icon: 'i-lucide-image',
      color: '#5e5ce6',
      title: 'Media Pipeline',
      sub: 'áudio/imagem',
    });
  list.push({
    icon: 'i-lucide-bot',
    color: '#1faa59',
    title: 'AI Agent',
    sub: props.model
      ? `${props.model}`
      : `LLM · temp ${cfg.temperature ?? 0.7}`,
    agent: true,
  });
  if (isOn('dedup'))
    list.push({
      icon: 'i-lucide-copy-slash',
      color: '#ff9500',
      title: 'Dedup',
      sub: bh.dedup?.ttl_seconds ? `TTL ${bh.dedup.ttl_seconds}s` : 'dedup',
    });
  if (isOn('humanizer'))
    list.push({
      icon: 'i-lucide-pen-tool',
      color: '#ff2d55',
      title: 'Humanizer',
      sub: bh.humanizer?.max_chars
        ? `${bh.humanizer.max_chars} chars`
        : 'humaniza',
    });
  list.push({
    icon: 'i-lucide-send',
    color: '#34c759',
    title: 'Response',
    sub: 'WhatsApp',
  });
  return list;
});

const nodes = computed(() =>
  mainSteps.value.map((n, i) => ({ ...n, x: i * (NODE_W + GAP), y: 0 }))
);
const agentNode = computed(
  () => nodes.value.find(n => n.agent) || nodes.value[0]
);
const handoff = computed(() => ({
  icon: 'i-lucide-user-check',
  color: '#ff3b30',
  title: 'Handoff',
  sub: 'Passa pra humano',
  x: agentNode.value.x,
  y: NODE_H + BRANCH_DY,
}));

const contentW = computed(
  () => nodes.value.length * NODE_W + (nodes.value.length - 1) * GAP
);
const contentH = computed(() => NODE_H + BRANCH_DY + NODE_H);

const hbez = (x1, y1, x2, y2) => {
  const dx = Math.max(34, (x2 - x1) / 2);
  return `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
};
const vbez = (x1, y1, x2, y2) => {
  const dy = Math.max(28, (y2 - y1) / 2);
  return `M ${x1} ${y1} C ${x1} ${y1 + dy}, ${x2} ${y2 - dy}, ${x2} ${y2}`;
};

const edges = computed(() => {
  const ns = nodes.value;
  const arr = [];
  for (let i = 0; i < ns.length - 1; i += 1) {
    arr.push({
      d: hbez(ns[i].x + NODE_W, NODE_H / 2, ns[i + 1].x, NODE_H / 2),
      handoff: false,
    });
  }
  const a = agentNode.value;
  arr.push({
    d: vbez(
      a.x + NODE_W / 2,
      NODE_H,
      handoff.value.x + NODE_W / 2,
      handoff.value.y
    ),
    handoff: true,
  });
  return arr;
});

const handles = computed(() => {
  const ns = nodes.value;
  const pts = [];
  ns.forEach((n, i) => {
    if (i > 0) pts.push({ x: n.x, y: NODE_H / 2 });
    if (i < ns.length - 1) pts.push({ x: n.x + NODE_W, y: NODE_H / 2 });
  });
  const a = agentNode.value;
  pts.push({ x: a.x + NODE_W / 2, y: NODE_H });
  pts.push({ x: handoff.value.x + NODE_W / 2, y: handoff.value.y });
  return pts;
});

// ---- pan / zoom / fit ----
const viewport = ref(null);
const panX = ref(0);
const panY = ref(0);
const zoom = ref(1);
const layerStyle = computed(() => ({
  transform: `translate(${panX.value}px, ${panY.value}px) scale(${zoom.value})`,
  transformOrigin: '0 0',
}));
const gridStyle = computed(() => ({
  backgroundSize: `${18 * zoom.value}px ${18 * zoom.value}px`,
  backgroundPosition: `${panX.value}px ${panY.value}px`,
}));
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

function fit() {
  const el = viewport.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  if (!r.width) return;
  const pad = 56;
  const s = clamp(
    Math.min(
      (r.width - pad) / contentW.value,
      (r.height - pad) / contentH.value
    ),
    0.4,
    1.4
  );
  zoom.value = s;
  panX.value = (r.width - contentW.value * s) / 2;
  panY.value = (r.height - contentH.value * s) / 2;
}
function zoomAt(mx, my, factor) {
  const nz = clamp(zoom.value * factor, 0.4, 2);
  const k = nz / zoom.value;
  panX.value = mx - (mx - panX.value) * k;
  panY.value = my - (my - panY.value) * k;
  zoom.value = nz;
}
function onWheel(e) {
  const r = viewport.value.getBoundingClientRect();
  zoomAt(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.12 : 1 / 1.12);
}
function ctrlZoom(factor) {
  const r = viewport.value.getBoundingClientRect();
  zoomAt(r.width / 2, r.height / 2, factor);
}

const dragging = ref(false);
let sx = 0;
let sy = 0;
let bpx = 0;
let bpy = 0;
function onMove(e) {
  panX.value = bpx + (e.clientX - sx);
  panY.value = bpy + (e.clientY - sy);
}
function onUp() {
  dragging.value = false;
  window.removeEventListener('pointermove', onMove);
  window.removeEventListener('pointerup', onUp);
}
function onDown(e) {
  dragging.value = true;
  sx = e.clientX;
  sy = e.clientY;
  bpx = panX.value;
  bpy = panY.value;
  window.addEventListener('pointermove', onMove);
  window.addEventListener('pointerup', onUp);
}
onMounted(() => nextTick(() => setTimeout(fit, 60)));
onBeforeUnmount(onUp);

const ZOOM_LABEL = computed(() => `${Math.round(zoom.value * 100)}%`);
</script>

<template>
  <div
    ref="viewport"
    class="relative overflow-hidden rounded-2xl border select-none canvas border-n-weak bg-n-alpha-1 h-[460px]"
    :class="dragging ? 'cursor-grabbing' : 'cursor-grab'"
    :style="gridStyle"
    @wheel.prevent="onWheel"
    @pointerdown="onDown"
  >
    <div class="absolute top-0 left-0" :style="layerStyle">
      <svg
        :width="contentW"
        :height="contentH"
        class="overflow-visible absolute top-0 left-0 pointer-events-none"
      >
        <path
          v-for="(e, i) in edges"
          :key="`b${i}`"
          :d="e.d"
          fill="none"
          stroke-width="2"
          :class="e.handoff ? 'edge-base-h' : 'edge-base'"
        />
        <path
          v-for="(e, i) in edges"
          :key="`f${i}`"
          :d="e.d"
          fill="none"
          stroke-width="2"
          stroke-linecap="round"
          :class="e.handoff ? 'edge-flow-h' : 'edge-flow'"
        />
        <circle
          v-for="(p, i) in handles"
          :key="`h${i}`"
          :cx="p.x"
          :cy="p.y"
          r="4.5"
          class="handle"
        />
      </svg>

      <div
        v-for="(n, i) in nodes"
        :key="i"
        class="flex absolute gap-2.5 items-center px-3 rounded-2xl border shadow-sm fg-node border-n-weak bg-n-solid-1"
        :style="{
          left: `${n.x}px`,
          top: `${n.y}px`,
          width: `${NODE_W}px`,
          height: `${NODE_H}px`,
          animationDelay: `${i * 55}ms`,
        }"
      >
        <span
          class="grid flex-none place-items-center text-white shadow-sm rounded-xl size-11"
          :style="{ background: n.color }"
        >
          <span :class="n.icon" class="size-5" />
        </span>
        <div class="min-w-0">
          <p
            class="text-[13.5px] font-bold leading-tight truncate text-n-slate-12"
          >
            {{ n.title }}
          </p>
          <p
            v-if="n.sub"
            class="text-[11px] leading-tight truncate text-n-slate-10"
          >
            {{ n.sub }}
          </p>
        </div>
      </div>

      <div
        class="flex absolute gap-2.5 items-center px-3 rounded-2xl border shadow-sm fg-node border-r-300 bg-r-50 dark:bg-r-900/20 dark:border-r-800"
        :style="{
          left: `${handoff.x}px`,
          top: `${handoff.y}px`,
          width: `${NODE_W}px`,
          height: `${NODE_H}px`,
        }"
      >
        <span
          class="grid flex-none place-items-center text-white shadow-sm rounded-xl size-11"
          :style="{ background: handoff.color }"
        >
          <span :class="handoff.icon" class="size-5" />
        </span>
        <div class="min-w-0">
          <p
            class="text-[13.5px] font-bold leading-tight truncate text-n-slate-12"
          >
            {{ handoff.title }}
          </p>
          <p class="text-[11px] leading-tight truncate text-n-slate-10">
            {{ handoff.sub }}
          </p>
        </div>
      </div>
    </div>

    <!-- Controles de zoom (fixos) -->
    <div
      class="flex absolute bottom-3 left-3 gap-1 items-center p-1 rounded-xl border shadow-sm border-n-weak bg-n-solid-1/90 backdrop-blur"
    >
      <button
        type="button"
        class="grid place-items-center rounded-lg transition size-7 text-n-slate-11 hover:bg-n-alpha-2"
        @pointerdown.stop
        @click="ctrlZoom(1 / 1.2)"
      >
        <span class="i-lucide-minus size-4" />
      </button>
      <span
        class="w-10 text-[11px] font-semibold text-center tabular-nums text-n-slate-11"
        >{{ ZOOM_LABEL }}</span
      >
      <button
        type="button"
        class="grid place-items-center rounded-lg transition size-7 text-n-slate-11 hover:bg-n-alpha-2"
        @pointerdown.stop
        @click="ctrlZoom(1.2)"
      >
        <span class="i-lucide-plus size-4" />
      </button>
      <span class="mx-0.5 w-px h-5 bg-n-weak" />
      <button
        type="button"
        class="grid place-items-center rounded-lg transition size-7 text-n-slate-11 hover:bg-n-alpha-2"
        @pointerdown.stop
        @click="fit"
      >
        <span class="i-lucide-maximize-2 size-4" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.canvas {
  background-image: radial-gradient(
    circle,
    rgba(100, 116, 139, 0.2) 1px,
    transparent 1px
  );
}
:global(.dark) .canvas {
  background-image: radial-gradient(
    circle,
    rgba(148, 163, 184, 0.18) 1px,
    transparent 1px
  );
}
.edge-base {
  stroke: rgba(31, 170, 89, 0.25);
}
.edge-base-h {
  stroke: rgba(255, 59, 48, 0.28);
}
.edge-flow {
  stroke: #1faa59;
  stroke-dasharray: 5 9;
  animation: edge-run 0.9s linear infinite;
}
.edge-flow-h {
  stroke: #ff3b30;
  stroke-dasharray: 5 9;
  animation: edge-run 0.9s linear infinite;
}
@keyframes edge-run {
  to {
    stroke-dashoffset: -14;
  }
}
.handle {
  fill: #ffffff;
  stroke: rgba(100, 116, 139, 0.55);
  stroke-width: 1.5;
}
:global(.dark) .handle {
  fill: #1c1c1e;
}
.fg-node {
  animation: fg-rise 0.4s cubic-bezier(0.22, 1, 0.36, 1) both;
}
@keyframes fg-rise {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@media (prefers-reduced-motion: reduce) {
  .edge-flow,
  .edge-flow-h {
    animation: none;
  }
  .fg-node {
    animation: none;
  }
}
</style>
