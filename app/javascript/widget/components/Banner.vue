<script>
import WBanner from 'widget/ui/WBanner.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

/**
 * A faixa de alerta transitória do widget — MIGRADA no bloco 2.07.
 *
 * Era o único dos quatro arquivos do bloco que nunca havia sido tocado, e
 * carregava três dívidas na mesma folha de estilo:
 *
 *   · `text-white` literal (aceite 4 da §C.15) — cor cravada que não segue
 *     tema nenhum e reprova o mesmo lint que os 13 primitivos passam;
 *   · `bg-n-ruby-9` / `bg-n-teal-9` cravados, os dois tons mais saturados da
 *     escala, num retângulo de largura inteira colado sob o cabeçalho;
 *   · nenhum papel ARIA. Uma falha de upload aparecia por 3 s e sumia, e quem
 *     usa leitor de tela nunca soube que ela existiu.
 *
 * Agora ela DELEGA ao `WBanner`, o primitivo do 2.01, que é quem sabe a
 * correspondência entre tom e papel: `error` vira `role="alert"` (interrompe,
 * porque o visitante precisa saber AGORA que o anexo não subiu) e `success`
 * vira `role="status"` (espera a pausa).
 *
 * ── O QUE NÃO MUDOU, DE PROPÓSITO ────────────────────────────────────────────
 *
 * O contrato do barramento é o mesmo: `SHOW_ALERT` com `{ message, type }`,
 * `type` faltando significa `error`, e a faixa se apaga sozinha em 3 s. Os
 * cinco emissores (`useConversationFooter`, `ChatAttachment`) continuam
 * intocados.
 *
 * E ela continua fora do composer: vive entre o cabeçalho e o `<main>` em
 * `ViewWithHeader.vue`, empurrando o conteúdo, nunca cobrindo o campo de texto.
 */
const DURACAO_MS = 3000;

/** O barramento manda `error`/`success`; o primitivo fala em tons. */
const TOM_POR_TIPO = { error: 'error', success: 'success' };

export default {
  components: { WBanner },
  data() {
    return {
      showBannerMessage: false,
      bannerMessage: '',
      bannerType: 'error',
      temporizador: null,
    };
  },
  computed: {
    tom() {
      return TOM_POR_TIPO[this.bannerType] || 'error';
    },
  },
  mounted() {
    this.aoAlertar = ({ message, type = 'error' }) => {
      this.bannerMessage = message;
      this.bannerType = type;
      this.showBannerMessage = true;
      // Um segundo alerta dentro dos 3 s reiniciava o relógio do primeiro e o
      // temporizador antigo continuava vivo, apagando a faixa nova antes da
      // hora. Guardar a referência e cancelá-la é o que faz dois erros
      // seguidos de upload serem os dois legíveis.
      if (this.temporizador) clearTimeout(this.temporizador);
      this.temporizador = setTimeout(() => {
        this.showBannerMessage = false;
        this.temporizador = null;
      }, DURACAO_MS);
    };
    emitter.on(BUS_EVENTS.SHOW_ALERT, this.aoAlertar);
  },
  unmounted() {
    emitter.off(BUS_EVENTS.SHOW_ALERT, this.aoAlertar);
    if (this.temporizador) clearTimeout(this.temporizador);
  },
};
</script>

<!-- A faixa não existe fora do alerta, e um `v-else` vazio só acrescentaria nó
     ao DOM da tela. Mesmo tratamento que `ConnectionBanner.vue`. -->
<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <WBanner v-if="showBannerMessage" :tone="tom" class="w-alert-banner">
    {{ bannerMessage }}
  </WBanner>
</template>

<style scoped lang="scss">
.w-alert-banner {
  @apply mx-3 mt-2;
}
</style>
