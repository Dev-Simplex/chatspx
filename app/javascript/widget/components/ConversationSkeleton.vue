<script>
import WSkeleton from 'widget/ui/WSkeleton.vue';
import WSpinner from 'widget/ui/WSpinner.vue';
import { widgetLoadingGate } from 'widget/state';

/**
 * O CONSUMIDOR do portão de carregamento — bloco 2.07.
 *
 * Mesma história do `ConnectionBanner`: `loadingGate.js` existia, tinha teste
 * verde e nenhum leitor. Aqui ele ganha um.
 *
 * O portão é quem segura os 600 ms; este componente só liga e desliga o
 * cronômetro conforme a lista está sendo buscada. Um `setTimeout` escrito aqui
 * dentro faria a mesma coisa e seria impossível de medir sem montar a tela.
 *
 * O esqueleto é `aria-hidden` (é do próprio `WSkeleton`), então quem ANUNCIA o
 * carregamento é o `WSpinner`, com `role="status"` e rótulo — caixas cinzas
 * lidas em voz alta são ruído, ausência de anúncio é informação perdida.
 */
export default {
  name: 'ConversationSkeleton',
  components: { WSkeleton, WSpinner },
  props: {
    /** `true` enquanto a lista de mensagens está sendo buscada. */
    loading: { type: Boolean, default: false },
    /** Ver a nota do `monitor` em `ConnectionBanner.vue`. */
    gate: {
      type: Object,
      default: () => widgetLoadingGate,
    },
  },
  data() {
    return { visivel: this.gate.isVisible };
  },
  watch: {
    loading: {
      immediate: true,
      handler(carregando) {
        if (carregando) this.gate.start();
        else this.gate.stop();
      },
    },
  },
  mounted() {
    this.visivel = this.gate.isVisible;
    this.desinscrever = this.gate.subscribe(visivel => {
      this.visivel = visivel;
    });
  },
  unmounted() {
    this.desinscrever?.();
    // Sair da tela com o cronômetro correndo deixaria o esqueleto "aceso" para
    // a próxima montagem, sem carregamento nenhum acontecendo.
    this.gate.stop();
  },
};
</script>

<!-- O esqueleto simplesmente NÃO existe fora do carregamento, e um `v-else`
     vazio só acrescentaria nó ao DOM. Mesmo tratamento que `Banner.vue`. -->
<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="visivel" class="w-conversation-skeleton">
    <WSpinner class="sr-only" :label="$t('CONNECTION.LOADING')" />
    <WSkeleton :lines="3" />
  </div>
</template>

<style scoped lang="scss">
.w-conversation-skeleton {
  @apply py-2;
}
</style>
