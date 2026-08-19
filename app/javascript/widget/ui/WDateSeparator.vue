<script>
import { formatDate } from 'shared/helpers/DateHelper';

/**
 * Separador de data da conversa — bloco 2.04 (§C.4 item 4).
 *
 * ── Por que um primitivo do widget em vez de mexer no compartilhado ──────────
 *
 * `shared/components/DateSeparator.vue` também é renderizado pelo
 * `MessageList.vue` do DASHBOARD. Trocá-lo pela pílula mudaria a tela do agente
 * de tabela, que não é o que este bloco pede e cuja régua visual está noutra
 * onda. Um primitivo próprio deixa as duas superfícies evoluírem sem uma
 * arrastar a outra — que é a mesma razão de `widget/ui/` existir.
 *
 * ── O que muda em relação ao compartilhado ────────────────────────────────────
 *
 * Ele desenhava a data solta, com duas linhas horizontais em `::before`/`::after`
 * e ALTURA FIXA de 50 px (`h-[50px] leading-[50px]`). Altura fixa em elemento
 * com texto quebra quando o visitante aumenta a fonte do navegador — é o aceite
 * 5 da §C.5, "nenhuma altura fixa em px em elemento com texto".
 *
 * A pílula não tem altura fixa: ela é o texto mais padding sobre `n-solid-1` —
 * a superfície ELEVADA do widget, que é o oposto de `--w-surface-sunken` (a
 * lista, bloco 2.04) e por isso destaca a etiqueta do fundo nos dois temas sem
 * precisar de cor própria. A data lê como etiqueta em vez de título de seção.
 */
export default {
  name: 'WDateSeparator',
  props: {
    date: {
      type: [String, Date, Number],
      required: true,
    },
  },
  computed: {
    dataFormatada() {
      return formatDate({
        date: this.date,
        todayText: this.$t('TODAY'),
        yesterdayText: this.$t('YESTERDAY'),
      });
    },
  },
};
</script>

<template>
  <div class="w-date-separator">
    <!-- `<time>` porque é data, e o leitor de tela anuncia "Hoje" como
         etiqueta em vez de como parágrafo solto no meio da conversa. -->
    <time class="w-date-separator__pilula">{{ dataFormatada }}</time>
  </div>
</template>

<style scoped lang="scss">
.w-date-separator {
  @apply flex justify-center my-5;

  &__pilula {
    @apply inline-block rounded-full px-3 py-1 text-xs font-medium
      bg-n-solid-1 text-n-slate-11;
  }
}
</style>
