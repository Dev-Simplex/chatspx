<script setup>
// Campo rotulado do painel de configuração: label em cima, controle no slot, dica opcional
// embaixo. Mantém o espaçamento consistente entre todos os editores de nó.
defineProps({
  label: {
    type: String,
    default: '',
  },
  hint: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <label class="flex flex-col gap-1.5">
    <span
      v-if="label"
      class="text-xs font-medium text-n-slate-11"
      data-testid="config-field-label"
    >
      {{ label }}
    </span>
    <slot />
    <span v-if="hint" class="text-xs leading-snug text-n-slate-10">
      {{ hint }}
    </span>
  </label>
</template>
