<script>
// Blocos 1.03/1.04 — o getter `appConfig/getWidgetColor` saiu junto com os dois
// `:style` que o consumiam. Este componente não lê mais cor nenhuma: borda e
// rótulo vêm de `--w-brand-readable`, o token que o servidor já escureceu até
// 4,5:1 (1.02). Um chip de resposta rápida pintado com a marca CRUA ficava em
// 2,27:1 sobre o branco — e o inline vencia a classe que o corrigia.
export default {
  components: {},
  props: {
    action: {
      type: Object,
      default: () => {},
    },
    isSelected: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['optionSelect'],
  methods: {
    onClick() {
      this.$emit('optionSelect', this.action);
    },
  },
};
</script>

<template>
  <li class="option" :class="{ 'is-selected': isSelected }">
    <button class="option-button button" @click="onClick">
      <span>{{ action.title }}</span>
    </button>
  </li>
</template>

<style scoped lang="scss">
.option {
  @apply rounded-[5rem] border border-solid border-w-brand-readable ltr:float-left rtl:float-right m-1 max-w-full;

  .option-button {
    // `text-w-brand-readable` é obrigatório aqui, e não decoração: o chip também
    // carrega a classe global `.button` (`woot.scss`), cujo `@apply` traz
    // `text-w-on-brand` — a cor legível sobre um fundo de marca que este botão
    // acabou de zerar com `bg-transparent`. Sem esta linha o rótulo herdaria a
    // cor pensada para outro fundo. Vence por especificidade: no CSS emitido a
    // regra escopada é `.option-button[data-v-…]` (0,2,0) contra `.button`
    // (0,1,0).
    @apply bg-transparent text-w-brand-readable border-0 cursor-pointer h-auto leading-normal ltr:text-left rtl:text-right whitespace-normal rounded-[2rem] min-h-[2.5rem];

    span {
      display: inline-block;
      vertical-align: middle;
    }
  }
}
</style>
