<script setup>
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

/** Tema do widget: claro, escuro ou automático (o do sistema do visitante). */
defineProps({
  modelValue: { type: String, default: 'auto' },
});

defineEmits(['update:modelValue']);

const { t } = useI18n();

const MODES = ['light', 'dark', 'auto'];
</script>

<template>
  <div class="grid gap-3 sm:grid-cols-3">
    <RadioCard
      v-for="mode in MODES"
      :id="`theme-${mode}`"
      :key="mode"
      :label="t(`INBOX_WIDGET.APPEARANCE.THEME.${mode.toUpperCase()}.LABEL`)"
      :description="
        t(`INBOX_WIDGET.APPEARANCE.THEME.${mode.toUpperCase()}.DESCRIPTION`)
      "
      :is-active="modelValue === mode"
      :data-testid="`theme-${mode}`"
      @select="$emit('update:modelValue', mode)"
    />
  </div>
</template>
