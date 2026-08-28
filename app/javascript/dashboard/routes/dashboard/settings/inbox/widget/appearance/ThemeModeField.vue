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

    <!-- O `<input type="radio">` do `RadioCard` nasce SEM nome acessivel: o
         titulo do cartao e um `<h3>` e o componente nao amarra um ao outro.
         Medido nesta tela com axe-core: regra `label`, impacto CRITICAL, sete
         nos, nos dois temas — "Element does not have an implicit (wrapped)
         <label> ... aria-label attribute does not exist".

         A correcao de raiz e no proprio `RadioCard` (`id` no `<h3>` +
         `aria-labelledby` no `input`), e resolveria o painel inteiro de uma
         vez; ela esta ESCALADA, porque `components-next/radioCard/` pertence a
         outra trilha. Enquanto isso o rotulo vive aqui, que e o remedio que o
         proprio axe pede.

         Fica DENTRO do grid de proposito: `sr-only` posiciona em `absolute`, e
         um filho absoluto nao e item de grid — nao ocupa celula, nao mexe no
         `auto-fit`, e o componente continua com raiz unica. E e `sr-only`
         porque o texto ja esta visivel no cartao: repeti-lo na tela seria
         corrigir um defeito de leitor de tela criando um defeito de olho. -->
    <label
      v-for="mode in MODES"
      :key="`label-${mode}`"
      :for="`theme-${mode}`"
      class="sr-only"
    >
      {{ t(`INBOX_WIDGET.APPEARANCE.THEME.${mode.toUpperCase()}.LABEL`) }}
    </label>
  </div>
</template>
