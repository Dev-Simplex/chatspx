<script setup>
import { Handle, Position } from '@vue-flow/core';

const props = defineProps({
  data: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['nodeClick']);

function handleClick() {
  if (props.data.behaviorKey) {
    emit('nodeClick', props.data.behaviorKey);
  }
}
</script>

<template>
  <div
    class="flex items-center gap-2.5 rounded-xl border-2 px-4 py-3 shadow-sm min-w-[160px] cursor-default select-none"
    :class="[
      data.enabled
        ? [data.style.bg, data.style.border]
        : 'opacity-40 border-dashed border-n-weak bg-n-alpha-1',
    ]"
    @click="handleClick"
  >
    <div
      v-if="data.enabled"
      class="flex size-7 items-center justify-center rounded-lg"
      :class="data.style.iconBg || 'bg-white/50 dark:bg-black/20'"
    >
      <i
        class="size-3.5"
        :class="[
          `i-lucide-${data.style.icon}`,
          data.style.iconColor || 'text-n-slate-12',
        ]"
      />
    </div>
    <div>
      <div class="text-xs font-semibold text-n-slate-12">
        {{ data.label }}
      </div>
      <div
        v-if="data.summary && data.enabled"
        class="mt-0.5 text-[10px] text-n-slate-10"
      >
        {{ data.summary }}
      </div>
    </div>
    <Handle
      type="target"
      :position="Position.Left"
      class="!size-2 !rounded-full !border-0 !bg-n-slate-8"
    />
    <Handle
      type="source"
      :position="Position.Right"
      class="!size-2 !rounded-full !border-0 !bg-n-slate-8"
    />
  </div>
</template>
