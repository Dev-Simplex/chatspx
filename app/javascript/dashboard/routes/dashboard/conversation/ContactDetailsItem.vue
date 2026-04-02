<script>
export default {
  props: {
    title: { type: String, required: true },
    value: { type: [String, Number], default: '' },
    compact: { type: Boolean, default: false },
  },
};
</script>

<template>
  <div class="overflow-auto" :class="compact ? 'py-0 px-0' : 'py-1.5 px-0'">
    <div class="items-center flex justify-between mb-1">
      <span class="text-xs text-n-slate-10">
        {{ title }}
      </span>
      <slot name="button" />
    </div>
    <div v-if="value" class="break-words text-sm text-n-slate-12">
      <slot>
        {{ value }}
      </slot>
    </div>
  </div>
</template>
