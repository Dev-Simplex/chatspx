<script setup>
// Campo de hora (HH:MM) iOS.
defineProps({ modelValue: { type: String, default: '' } });
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiTimeField' });
</script>

<template>
  <input
    type="time"
    :value="modelValue"
    class="reset-base px-3 py-2 text-sm rounded-xl border outline-none transition border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:ring-2 focus:ring-n-brand/30 [&::-webkit-calendar-picker-indicator]:opacity-60 [&::-webkit-calendar-picker-indicator]:dark:invert"
    @input="$emit('update:modelValue', $event.target.value)"
  />
</template>
