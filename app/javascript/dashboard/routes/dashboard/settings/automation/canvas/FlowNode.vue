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
</script>

<template>
  <div
    class="relative flex items-stretch w-64 overflow-hidden border rounded-xl bg-n-solid-1 border-n-weak shadow-sm transition-shadow"
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
    <span class="w-1 shrink-0" :style="{ backgroundColor: familyMeta.color }" />
    <div class="flex flex-col min-w-0 gap-0.5 px-3 py-2.5">
      <span
        class="text-[10px] font-bold tracking-wider uppercase"
        :style="{ color: familyMeta.color }"
      >
        {{ familyLabel }}
      </span>
      <span class="text-sm font-semibold truncate text-n-slate-12">{{
        label
      }}</span>
      <span v-if="subtitle" class="text-xs truncate text-n-slate-11">{{
        subtitle
      }}</span>
    </div>
    <Handle
      type="source"
      :position="Position.Bottom"
      :style="{ backgroundColor: familyMeta.color }"
    />
  </div>
</template>
