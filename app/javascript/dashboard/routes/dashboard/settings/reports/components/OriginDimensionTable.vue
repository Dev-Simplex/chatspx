<script setup>
/**
 * Bloco 1.22 — uma dimensao do relatorio de origem (source, medium, campaign, tipo).
 *
 * O titulo chega pronto por prop para que cada chamador use uma chave de i18n LITERAL: chave
 * dinamica escapa do rastreio do lint e vira string faltando em producao sem ninguem perceber.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  title: { type: String, required: true },
  rows: { type: Array, default: () => [] },
  testid: { type: String, required: true },
  // Mapa valor-cru -> rotulo humano. Sem ele a coluna mostra `busca_paga` e `nao_disponivel`,
  // que sao valores de MAQUINA: o cliente nao le snake_case, e `nao_disponivel` ficaria dizendo
  // a mesma coisa que "origem nao disponivel" em outra lingua so nessa dimensao.
  valueLabels: { type: Object, default: null },
});

const { t } = useI18n();

const total = computed(() =>
  props.rows.reduce((soma, linha) => soma + linha.count, 0)
);

// `value` nulo e a conversa medida que nao trouxe o parametro: ela e "origem nao disponivel",
// e nunca "origem direta" — nao sabemos que o acesso foi direto, sabemos que faltou dado.
const labelFor = value => {
  if (value === null || value === undefined || value === '') {
    return t('ORIGIN_REPORTS.UNAVAILABLE');
  }
  return props.valueLabels?.[value] ?? value;
};

const shareLabel = count =>
  `${total.value ? Math.round((count / total.value) * 1000) / 10 : 0}%`;
</script>

<template>
  <section :data-testid="testid" class="flex flex-col gap-2">
    <h3 class="text-heading-3 text-n-slate-12">{{ title }}</h3>
    <table class="w-full text-body-main">
      <thead>
        <tr class="text-left text-n-slate-12">
          <th class="py-2 font-medium">
            {{ $t('ORIGIN_REPORTS.TABLE.VALUE') }}
          </th>
          <th class="py-2 font-medium text-right">
            {{ $t('ORIGIN_REPORTS.TABLE.CONVERSATIONS') }}
          </th>
          <th class="py-2 font-medium text-right">
            {{ $t('ORIGIN_REPORTS.TABLE.SHARE') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.value ?? 'unavailable'"
          class="border-t border-n-weak"
        >
          <td
            class="py-2 text-n-slate-12"
            :class="{ 'italic text-n-slate-11': row.value === null }"
          >
            {{ labelFor(row.value) }}
          </td>
          <td class="py-2 text-right tabular-nums">{{ row.count }}</td>
          <td class="py-2 text-right tabular-nums text-n-slate-12">
            {{ shareLabel(row.count) }}
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
