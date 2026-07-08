<script setup>
// Aresta customizada do canvas Flow. Desenha o caminho smoothstep e, quando a aresta carrega
// um ramo (`data.label` — "Sim"/"Não"/nome da rota), mostra um pill no meio identificando-o.
// Um botão × no pill remove a aresta via useVueFlow().removeEdges — o FlowCanvasView escuta o
// `edges-change` resultante e sincroniza a definition (fonte da verdade). Reusa BaseEdge para
// o traçado nativo (marker/seleção) e EdgeLabelRenderer para posicionar o rótulo em tela.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  useVueFlow,
  Position,
} from '@vue-flow/core';

const props = defineProps({
  id: { type: String, required: true },
  sourceX: { type: Number, required: true },
  sourceY: { type: Number, required: true },
  targetX: { type: Number, required: true },
  targetY: { type: Number, required: true },
  sourcePosition: { type: String, default: Position.Bottom },
  targetPosition: { type: String, default: Position.Top },
  markerEnd: { type: String, default: '' },
  style: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  data: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const { removeEdges } = useVueFlow();

// [path, labelX, labelY] — labelX/Y é o ponto médio onde ancoramos o pill.
const pathData = computed(() =>
  getSmoothStepPath({
    sourceX: props.sourceX,
    sourceY: props.sourceY,
    sourcePosition: props.sourcePosition,
    targetX: props.targetX,
    targetY: props.targetY,
    targetPosition: props.targetPosition,
  })
);

const label = computed(() => props.data?.label || '');
const color = computed(() => props.data?.color || null);

const onRemove = () => removeEdges([props.id]);
</script>

<template>
  <BaseEdge
    :id="id"
    :path="pathData[0]"
    :marker-end="markerEnd"
    :style="style"
  />
  <EdgeLabelRenderer>
    <div
      :style="{
        transform: `translate(-50%, -50%) translate(${pathData[1]}px, ${pathData[2]}px)`,
      }"
      class="nodrag nopan group absolute pointer-events-auto flex items-center gap-1"
      data-testid="flow-edge-label"
    >
      <span
        v-if="label"
        class="px-1.5 py-0.5 text-[10px] font-semibold leading-none rounded-full border shadow-sm bg-n-solid-1 border-n-weak text-n-slate-12"
        :style="color ? { color, borderColor: color } : {}"
      >
        {{ label }}
      </span>
      <button
        type="button"
        class="grid transition-opacity rounded-full opacity-0 size-4 place-items-center bg-n-solid-1 border border-n-weak text-n-slate-11 hover:text-n-ruby-11 hover:border-n-ruby-9 group-hover:opacity-100"
        :class="{ 'opacity-100': selected }"
        :aria-label="t('AUTOMATION.CANVAS.CONFIG.EDGE.REMOVE')"
        data-testid="flow-edge-remove"
        @click.stop="onRemove"
      >
        <span class="i-lucide-x text-[10px]" />
      </button>
    </div>
  </EdgeLabelRenderer>
</template>
