<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { VueFlow } from '@vue-flow/core';
import { Background } from '@vue-flow/background';
import { Controls } from '@vue-flow/controls';
import { MiniMap } from '@vue-flow/minimap';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import FlowNode from './FlowNode.vue';
import { NODE_CATALOG, FAMILIES, familyForNode } from './nodeCatalog';

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

const name = ref('');
const definition = ref({ nodes: [], edges: [] });
const isSaving = ref(false);

const nodeTypes = { flow: FlowNode };

const vfNodes = computed(() =>
  (definition.value.nodes || []).map((node, index) => ({
    id: String(node.id),
    type: 'flow',
    position: { x: 180, y: index * 130 + 40 },
    data: { node },
  }))
);
const vfEdges = computed(() =>
  (definition.value.edges || [])
    .filter(edge => edge.to)
    .map(edge => ({
      id: `${edge.from}->${edge.to}`,
      source: String(edge.from),
      target: String(edge.to),
    }))
);

const nodeColor = node => {
  const raw = node.data?.node || {};
  return (FAMILIES[familyForNode(raw)] || FAMILIES.action).color;
};

onMounted(async () => {
  if (!isEdit.value) {
    name.value = t('AUTOMATION.CANVAS.NEW_FLOW');
    return;
  }
  let flow = store.getters['flows/getFlow'](flowId.value);
  if (!flow) flow = await store.dispatch('flows/show', flowId.value);
  if (flow) {
    name.value = flow.name;
    definition.value = flow.definition || { nodes: [], edges: [] };
  }
});

const nextNodeId = () => {
  const ids = (definition.value.nodes || []).map(
    n => parseInt(String(n.id).replace(/\D/g, ''), 10) || 0
  );
  return `n${(ids.length ? Math.max(...ids) : 0) + 1}`;
};

const addNode = item => {
  const id = nextNodeId();
  const node = { id, type: item.type };
  if (item.actionName) {
    node.action_name = item.actionName;
    node.action_params = [];
  }
  const nodes = [...(definition.value.nodes || []), node];
  const edges = [...(definition.value.edges || [])];
  const prev = definition.value.nodes[definition.value.nodes.length - 1];
  if (prev) edges.push({ from: prev.id, to: id });
  definition.value = { nodes, edges };
};

const save = async () => {
  isSaving.value = true;
  try {
    const hasTrigger = (definition.value.nodes || []).some(
      n => n.type === 'trigger'
    );
    const payload = {
      name: name.value,
      trigger_type: hasTrigger ? 'conversation_event' : 'manual',
      definition: definition.value,
    };
    if (isEdit.value) {
      await store.dispatch('flows/update', { id: flowId.value, ...payload });
      useAlert(t('AUTOMATION.CANVAS.SAVED'));
    } else {
      const created = await store.dispatch('flows/create', payload);
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

const goBack = () =>
  router.push({ name: 'automation_list', params: route.params });
</script>

<template>
  <div
    class="flex flex-col w-full h-full bg-n-solid-2"
    data-testid="flow-canvas-view"
  >
    <header
      class="flex items-center gap-3 px-4 border-b h-14 shrink-0 border-n-weak bg-n-solid-1"
    >
      <button
        class="text-n-slate-11 hover:text-n-slate-12"
        data-testid="canvas-back"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left" />
      </button>
      <input
        v-model="name"
        class="flex-1 max-w-md px-2 py-1 text-sm font-semibold bg-transparent rounded outline-none text-n-slate-12 focus:bg-n-solid-2"
        :placeholder="t('AUTOMATION.CANVAS.NAME_PLACEHOLDER')"
        data-testid="canvas-name"
      />
      <button
        class="px-3 py-1.5 text-sm font-medium text-white rounded-lg bg-n-brand disabled:opacity-60"
        :disabled="isSaving"
        data-testid="canvas-save"
        @click="save"
      >
        {{ t('AUTOMATION.CANVAS.SAVE') }}
      </button>
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
        <button
          v-for="item in NODE_CATALOG"
          :key="item.key"
          class="flex items-center gap-2 px-2 py-1.5 text-sm text-left rounded-lg text-n-slate-12 hover:bg-n-solid-3"
          :data-testid="`palette-${item.key}`"
          @click="addNode(item)"
        >
          <span
            class="w-2 h-2 rounded-full shrink-0"
            :style="{
              backgroundColor: (FAMILIES[item.family] || FAMILIES.action).color,
            }"
          />
          {{ item.label }}
        </button>
      </aside>

      <main class="relative flex-1 min-w-0">
        <VueFlow
          :nodes="vfNodes"
          :edges="vfEdges"
          :node-types="nodeTypes"
          :default-viewport="{ zoom: 0.9 }"
          fit-view-on-init
          class="w-full h-full"
        >
          <template #node-flow="nodeProps">
            <FlowNode v-bind="nodeProps" />
          </template>
          <Background :gap="16" />
          <Controls />
          <MiniMap :node-color="nodeColor" pannable zoomable />
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
    </div>
  </div>
</template>
