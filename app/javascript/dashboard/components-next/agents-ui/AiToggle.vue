<script setup>
defineProps({
  modelValue: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});
defineEmits(['update:modelValue']);
// Switch iOS 46x28.
defineOptions({ name: 'AiToggle' });
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    :disabled="disabled"
    class="relative w-[46px] h-[28px] rounded-full transition-colors duration-200 flex-none disabled:opacity-50"
    :class="modelValue ? 'bg-n-brand' : 'bg-n-slate-5'"
    @click="$emit('update:modelValue', !modelValue)"
  >
    <span
      class="absolute top-[2px] left-[2px] bg-white rounded-full shadow transition-transform duration-200 size-6"
      :class="modelValue ? 'translate-x-[18px]' : ''"
    />
  </button>
</template>
