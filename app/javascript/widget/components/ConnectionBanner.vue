<script>
import WBanner from 'widget/ui/WBanner.vue';
import { widgetConnectionMonitor } from 'widget/state';
import { CONNECTION_STATES } from 'widget/state/connectionMonitor';

/**
 * O CONSUMIDOR da máquina de estados de conexão — bloco 2.07.
 *
 * Até aqui `connectionMonitor.js` existia, tinha teste verde e NINGUÉM o lia: a
 * conexão caía, o monitor mudava de estado, e a tela do visitante continuava
 * dizendo que estava tudo bem. Este componente é o elo que faltava.
 *
 * Ele não decide nada. A carência de 3 s e o corte de 15 s moram no monitor,
 * onde são medidos com relógio falso; aqui só se desenha o estado que chega.
 *
 * ⚠️ O COMPOSER NÃO É TOCADO. A faixa é irmã da conversa, acima da lista, e não
 * cobre nem desabilita o campo de texto — quem está escrevendo continua
 * escrevendo. É metade do aceite do bloco ("composer utilizável"), e é por isso
 * que a faixa não é um overlay.
 */
const TOM_POR_ESTADO = {
  [CONNECTION_STATES.RECONNECTING]: 'warning',
  [CONNECTION_STATES.OFFLINE]: 'error',
};

const CHAVE_POR_ESTADO = {
  [CONNECTION_STATES.RECONNECTING]: 'CONNECTION.RECONNECTING',
  [CONNECTION_STATES.OFFLINE]: 'CONNECTION.OFFLINE',
};

export default {
  name: 'ConnectionBanner',
  components: { WBanner },
  props: {
    /**
     * O monitor a observar. O default é o singleton da página; a prop existe
     * para o preview e para o teste que precisa de um relógio próprio — não
     * para haver dois monitores no app de verdade.
     */
    monitor: {
      type: Object,
      default: () => widgetConnectionMonitor,
    },
  },
  data() {
    return { estado: this.monitor.state };
  },
  computed: {
    visivel() {
      return this.estado !== CONNECTION_STATES.ONLINE;
    },
    tom() {
      return TOM_POR_ESTADO[this.estado] || 'warning';
    },
    texto() {
      const chave = CHAVE_POR_ESTADO[this.estado];
      // A chave sai de `CHAVE_POR_ESTADO`, um mapa fechado deste arquivo, e não
      // de dado externo — que é o caso que a regra abaixo existe para pegar.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      return chave ? this.$t(chave) : '';
    },
  },
  mounted() {
    // O estado ATUAL é lido no mount, não só no evento: o componente pode nascer
    // com a conexão já caída (o visitante abre o widget sem rede), e um
    // consumidor que só escuta mudanças nasceria mudo nesse caso.
    this.estado = this.monitor.state;
    this.desinscrever = this.monitor.subscribe(estado => {
      this.estado = estado;
    });
  },
  unmounted() {
    this.desinscrever?.();
  },
};
</script>

<!-- A faixa simplesmente NÃO existe no estado normal, e um `v-else` vazio só
     acrescentaria nó ao DOM da conversa. Mesmo tratamento que `Banner.vue`. -->
<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <WBanner v-if="visivel" :tone="tom" class="w-connection-banner">
    {{ texto }}
  </WBanner>
</template>

<style scoped lang="scss">
.w-connection-banner {
  @apply mx-3 mt-2;
}
</style>
