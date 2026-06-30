<script setup>
// Textarea iOS — mesmo token/foco do AiField.
defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  rows: { type: Number, default: 3 },
});
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiTextarea' });
</script>

<template>
  <textarea
    :value="modelValue"
    :placeholder="placeholder"
    :rows="rows"
    class="px-3.5 py-2.5 w-full text-sm rounded-xl border outline-none transition resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:ring-2 focus:ring-n-brand/30"
    @input="$emit('update:modelValue', $event.target.value)"
  />
</template>
