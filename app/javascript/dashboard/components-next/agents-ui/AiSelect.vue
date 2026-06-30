<script setup>
// Select iOS — options [{ value, label }]. Chevron custom, foco n-brand.
defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, default: () => [] },
});
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiSelect' });
</script>

<template>
  <div class="relative">
    <select
      :value="modelValue"
      class="block reset-base py-2.5 pr-9 pl-3.5 w-full text-sm leading-none rounded-xl border outline-none transition appearance-none cursor-pointer border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:ring-2 focus:ring-n-brand/30"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option v-for="o in options" :key="o.value" :value="o.value">
        {{ o.label }}
      </option>
    </select>
    <span
      class="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none i-lucide-chevron-down size-4 text-n-slate-10"
    />
  </div>
</template>

<style scoped>
/* Remove a seta nativa em todos os browsers (evita seta dupla). */
select {
  -webkit-appearance: none;
  -moz-appearance: none;
  appearance: none;
  background-image: none;
  /* mata o margin-bottom (1rem) que o form-field global injeta no select e
     que jogava o chevron 8px pra baixo (wrapper 56px vs select 40px). */
  margin: 0 !important;
}
select::-ms-expand {
  display: none;
}
</style>
