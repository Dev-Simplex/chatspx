<script setup>
// Busca iOS: lupa + input. type=search + autocomplete off + readonly-até-focar evita o autofill de e-mail do browser.
import { ref } from 'vue';

defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
});
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiSearch' });
// Gerenciadores de senha pulam campos readonly; liberamos só ao focar.
const ro = ref(true);
</script>

<template>
  <div class="relative">
    <span
      class="absolute left-3.5 top-1/2 z-[1] -translate-y-1/2 pointer-events-none i-lucide-search size-4 text-n-slate-10"
    />
    <input
      :value="modelValue"
      :placeholder="placeholder"
      :readonly="ro"
      type="search"
      name="ai-search"
      autocomplete="off"
      spellcheck="false"
      class="reset-base py-2.5 pr-3 pl-10 w-full text-sm rounded-xl border outline-none transition border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:ring-2 focus:ring-n-brand/30 [&::-webkit-search-cancel-button]:appearance-none"
      @input="$emit('update:modelValue', $event.target.value)"
      @focus="ro = false"
      @mousedown="ro = false"
      @blur="ro = true"
    />
  </div>
</template>
