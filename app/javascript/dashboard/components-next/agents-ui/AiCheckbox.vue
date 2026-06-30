<script setup>
// Checkbox iOS: caixa com check + label inline. Distinto do AiToggle (switch).
defineProps({
  modelValue: { type: Boolean, default: false },
  label: { type: String, default: '' },
});
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiCheckbox' });
</script>

<template>
  <button
    type="button"
    role="checkbox"
    :aria-checked="modelValue"
    class="flex gap-2.5 items-center text-left group"
    @click="$emit('update:modelValue', !modelValue)"
  >
    <span
      class="grid flex-none rounded-md border place-items-center transition-all size-[20px]"
      :class="
        modelValue
          ? 'bg-n-brand border-n-brand text-white'
          : 'border-n-weak bg-n-solid-1 group-hover:border-n-slate-8'
      "
    >
      <span v-if="modelValue" class="i-lucide-check size-3.5" />
    </span>
    <span v-if="label" class="text-[13.5px] text-n-slate-12">{{ label }}</span>
  </button>
</template>
