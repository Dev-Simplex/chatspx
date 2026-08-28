<script>
import Spinner from 'shared/components/Spinner.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

export default {
  components: {
    FluentIcon,
    Spinner,
  },
  props: {
    loading: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
};
</script>

<template>
  <!-- Este componente ficou SEM REFERÊNCIA desde o 2.05, que trocou o composer
       por `ComposerActions` + `WIconButton`. Recebe nome mesmo assim: enquanto
       o arquivo existir, ele é um botão só-ícone sem nome esperando ser
       remontado. A remoção é limpeza de outro bloco — aqui só se fecha o
       buraco de a11y. `A11Y.SEND_MESSAGE` é a mesma chave que o botão vivo
       usa em `ComposerActions.vue`. -->
  <button
    type="submit"
    :disabled="disabled"
    class="min-h-8 min-w-8 flex items-center justify-center ml-1 rounded-full bg-w-brand hover:bg-w-brand-hover transition-colors"
    :title="$t('A11Y.SEND_MESSAGE')"
    :aria-label="$t('A11Y.SEND_MESSAGE')"
  >
    <FluentIcon v-if="!loading" icon="send" class="text-white" />
    <Spinner v-else size="small" />
  </button>
</template>
