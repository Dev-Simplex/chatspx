<script setup>
import { ref, toRef } from 'vue';
import { VueFlow } from '@vue-flow/core';
import { Background } from '@vue-flow/background';
import '@vue-flow/core/dist/style.css';
import '@vue-flow/core/dist/theme-default.css';
import WorkflowNode from './nodes/WorkflowNode.vue';
import { useWorkflowBuilder } from './useWorkflowBuilder';

const props = defineProps({
  assistant: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['scrollToBehavior']);

const assistantRef = toRef(props, 'assistant');
const { nodes, edges } = useWorkflowBuilder(assistantRef);

const fitViewOnInit = ref(true);

function onNodeClick(behaviorKey) {
  emit('scrollToBehavior', behaviorKey);
}
</script>

<template>
  <div
    class="h-[320px] w-full rounded-lg border border-n-weak bg-white dark:bg-n-solid-2"
  >
    <VueFlow
      :nodes="nodes"
      :edges="edges"
      :fit-view-on-init="fitViewOnInit"
      :nodes-draggable="false"
      :nodes-connectable="false"
      :elements-selectable="false"
      :zoom-on-scroll="false"
      pan-on-scroll
      :min-zoom="0.5"
      :max-zoom="1.5"
      class="h-full w-full"
    >
      <template #node-workflow="nodeProps">
        <WorkflowNode :data="nodeProps.data" @node-click="onNodeClick" />
      </template>
      <Background variant="dots" pattern-color="rgba(148,163,184,0.3)" />
    </VueFlow>
  </div>
</template>
