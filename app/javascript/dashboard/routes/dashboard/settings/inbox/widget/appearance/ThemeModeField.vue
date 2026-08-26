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
  <!-- `sm:grid-cols-3` era cego para a largura REAL disponivel: os cartoes
       moram na coluna de 6/8 da `SettingsFieldSection`, que no widget da 351 px
       independentemente do viewport. Tres colunas ali viram 109 px por cartao,
       e "O widget abre sempre claro." quebrava em 4 linhas (a do automatico, em
       6) — medido em 1280 e 1440. `auto-fit` decide pela largura do container,
       nao pela da janela: cai para uma coluna quando so cabe uma. -->
  <div
    class="grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(190px,1fr))]"
  >
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
