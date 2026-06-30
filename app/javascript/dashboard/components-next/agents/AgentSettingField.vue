<script setup>
// Linha de campo do formulário do agente: rótulo + dica opcional + controle (slot).
// Slot `aside` opcional à direita do rótulo (ex.: contador de caracteres).
defineProps({
  label: { type: String, default: '' },
  hint: { type: String, default: '' },
});
defineOptions({ name: 'AgentSettingField' });
</script>

<template>
  <div class="space-y-1.5">
    <div class="flex gap-2 justify-between items-baseline">
      <label class="text-[13px] font-semibold text-n-slate-12">{{
        label
      }}</label>
      <slot name="aside" />
    </div>
    <p v-if="hint" class="text-[12px] leading-snug text-n-slate-10">
      {{ hint }}
    </p>
    <slot />
  </div>
</template>
