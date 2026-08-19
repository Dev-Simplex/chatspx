<script>
import { mapGetters } from 'vuex';
import CustomButton from 'shared/components/Button.vue';
import configMixin from 'widget/mixins/configMixin';

/**
 * A saida para o WhatsApp (bloco 4.08 / W3.6).
 *
 * O que ela resolve: no perfil de captura, 75,96% das empresas brasileiras
 * mandam o visitante para o WhatsApp — e quem redireciona converte mais. Hoje o
 * visitante que quer continuar por la sai do site, procura o numero no rodape e
 * comeca do zero, contando de novo o que ja tinha contado aqui.
 *
 * TRES REGRAS, e cada uma e um jeito conhecido de isso dar errado:
 *
 *  1. **`primaryExit: 'none'` esconde.** O perfil de suporte nao oferece saida:
 *     quem ja e cliente e esta num chamado nao deve ser empurrado para outro
 *     canal no meio da conversa.
 *  2. **Sem numero configurado, nao aparece.** Um botao "continuar no WhatsApp"
 *     que abre `wa.me/` sem destino leva o visitante para uma tela de erro do
 *     WhatsApp — pior que nao ter botao. Enquanto o servidor nao entregar o
 *     numero, o componente simplesmente nao existe (que e o comportamento de
 *     hoje).
 *  3. **O contexto vai no texto, e ele e curto e do PROPRIO visitante.** O que
 *     viaja e o nome do site e a primeira coisa que ELE escreveu. Nada de
 *     historico do agente, dado de outro contato ou identificador interno: a
 *     URL fica visivel na barra do WhatsApp dele e em qualquer log de proxy no
 *     meio do caminho.
 */
export default {
  components: { CustomButton },
  mixins: [configMixin],
  computed: {
    ...mapGetters({ messages: 'conversation/getMessages' }),

    /** So digitos: `wa.me` recusa qualquer outra coisa. */
    whatsAppNumber() {
      const bruto = this.channelConfig?.whatsAppExitNumber ?? '';
      return String(bruto).replace(/\D/g, '');
    },

    isVisible() {
      return this.hasWhatsAppExit && Boolean(this.whatsAppNumber);
    },

    /** A primeira mensagem do VISITANTE — o assunto, nas palavras dele. */
    firstVisitorMessage() {
      const mensagens = Object.values(this.messages ?? {});
      const doVisitante = mensagens.find(
        mensagem => mensagem.message_type === 0 && mensagem.content
      );
      return doVisitante?.content?.trim() ?? '';
    },

    contextText() {
      const site = this.channelConfig?.websiteName ?? '';
      const assunto = this.firstVisitorMessage;
      const partes = [
        this.$t('WHATSAPP_EXIT.CONTEXT_PREFIX', { site }),
        assunto
          ? this.$t('WHATSAPP_EXIT.CONTEXT_SUBJECT', { subject: assunto })
          : '',
      ];
      return partes.filter(Boolean).join(' ');
    },

    whatsAppUrl() {
      return `https://wa.me/${this.whatsAppNumber}?text=${encodeURIComponent(
        this.contextText
      )}`;
    },
  },
};
</script>

<template>
  <!-- eslint-disable-next-line vue/no-root-v-if -- sem perfil de captura ou sem
       numero, o certo e nao renderizar nada: um botao que abre `wa.me/` sem
       destino leva o visitante para uma tela de erro do WhatsApp -->
  <a
    v-if="isVisible"
    :href="whatsAppUrl"
    target="_blank"
    rel="noopener noreferrer"
    class="block"
    data-testid="whatsapp-exit"
  >
    <CustomButton class="font-medium" block>
      {{ $t('WHATSAPP_EXIT.BUTTON') }}
    </CustomButton>
  </a>
</template>
