<script>
import ChatMessage from 'widget/components/ChatMessage.vue';
import AgentTypingBubble from 'widget/components/AgentTypingBubble.vue';
import WDateSeparator from 'widget/ui/WDateSeparator.vue';
import WScrollToBottom from 'widget/ui/WScrollToBottom.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import Spinner from 'shared/components/Spinner.vue';
import { useDarkMode } from 'widget/composables/useDarkMode';
import { calcularAgrupamento } from 'widget/composables/useMessageGrouping';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import AiHandoffMark from 'widget/components/AiHandoffMark.vue';
import { annotateHandoffs } from 'widget/helpers/aiIdentity';
import { mapActions, mapGetters } from 'vuex';

// ── Bloco 2.04 — os três números do scroll ────────────────────────────────────
//
// TOLERANCIA_FIM (80 px): a distância do fim dentro da qual o visitante ainda
// conta como "está lendo o que chega". Vem da §C.4 do plano 22. Não é 0 porque
// o navegador arredonda `scrollTop` em telas com DPR fracionário e uma lista
// visualmente no fim mede 1 ou 2 px de sobra; não é 300 porque aí o salto
// voltaria a acontecer com o visitante já lendo histórico.
//
// GATILHO_PAGINACAO (100 px): o valor que já existia, preservado. Ele é do
// carregamento de mensagens antigas, não do auto-scroll, e os dois são
// decisões diferentes que por acaso leem o mesmo `scrollTop`.
//
// INTERVALO_SCROLL (100 ms): teto de ~10 execuções por segundo, que é o aceite
// 5 da §C.4. `handleScroll` estava ligado direto no evento, sem throttle: um
// scroll contínuo de dois segundos disparava ~120 vezes, cada uma lendo
// `scrollHeight` — leitura que força reflow.
const TOLERANCIA_FIM = 80;
const GATILHO_PAGINACAO = 100;
const INTERVALO_SCROLL = 100;

export default {
  name: 'ConversationWrap',
  components: {
    ChatMessage,
    AgentTypingBubble,
    WDateSeparator,
    WScrollToBottom,
    FluentIcon,
    AiHandoffMark,
    Spinner,
  },
  props: {
    groupedMessages: {
      type: Array,
      default: () => [],
    },
  },
  setup() {
    const { darkMode, prefersDarkMode } = useDarkMode();
    return { darkMode, prefersDarkMode };
  },
  data() {
    return {
      previousScrollHeight: 0,
      previousConversationSize: 0,
      // Quantas mensagens chegaram enquanto o visitante estava lendo para
      // cima. É o contador do botão "descer", e ele zera quando o visitante
      // volta ao fim — por rolagem ou pelo próprio botão.
      naoLidasAbaixo: 0,
      estaNoFim: true,
      ultimoScrollEm: 0,
      scrollAgendado: null,
    };
  },
  computed: {
    ...mapGetters({
      earliestMessage: 'conversation/getEarliestMessage',
      lastMessage: 'conversation/getLastMessage',
      allMessagesLoaded: 'conversation/getAllMessagesLoaded',
      isFetchingList: 'conversation/getIsFetchingList',
      conversationSize: 'conversation/getConversationSize',
      isAgentTyping: 'conversation/getIsAgentTyping',
      conversationAttributes: 'conversationAttributes/getConversationParams',
    }),
    // Bloco 2.10. Lia `darkMode` cru, então o valor `auto` — que agora é o
    // DEFAULT — caía sempre em `light-scheme`, mesmo com o sistema escuro e o
    // resto do painel já escuro. `prefersDarkMode` é o valor RESOLVIDO: é ele
    // que o `App.vue` usa para a classe `dark`, e as duas decisões precisam
    // sair da mesma fonte.
    colorSchemeClass() {
      return this.prefersDarkMode ? 'dark-scheme' : 'light-scheme';
    },
    // ── Bloco 2.02/2.03 — o agrupamento, calculado POR BLOCO DE DATA ─────────
    //
    // Este recorte não é detalhe: era o que o seletor de irmão adjacente fazia
    // sem dizer. Cada bloco de data é uma `<div class="messages-wrap">`
    // própria, então a primeira linha de um dia NUNCA teve irmão anterior — e
    // portanto nunca continuou o grupo do dia anterior. Rodar
    // `calcularAgrupamento` na conversa achatada mudaria justamente essa linha,
    // que é a mais visível da lista.
    agrupamentoPorBloco() {
      return this.groupedMessagesWithHandoff.map(bloco =>
        calcularAgrupamento(bloco.messages)
      );
    },
    // ── Bloco 2.12 — a terceira chave do `v-memo` ─────────────────────────────
    // As duas primeiras (a mensagem e a classe de agrupamento) cobrem o que
    // muda a linha. Esta cobre o que muda o TEXTO da linha sem mudar a
    // mensagem: o visitante trocando de idioma numa inbox com mais de um
    // habilitado. Sem ela, `RETRY`, `DOWNLOAD` e os rótulos de anexo ficariam
    // no idioma antigo até a mensagem se mexer — que pode ser nunca.
    idiomaAtual() {
      return this.$root.$i18n?.locale;
    },
    /**
     * Bloco 4.09 — a 1a das tres marcacoes: o marcador de SISTEMA no fluxo.
     *
     * A anotacao roda sobre o grupo INTEIRO e em ordem, porque handoff e uma
     * TRANSICAO: so se sabe que a equipe entrou comparando com quem falou antes.
     * Anotar mensagem por mensagem, dentro do filho, nao teria essa informacao.
     *
     * ── E por que ele passou a alimentar o `v-for` do template (2.04/2.12) ────
     *
     * `annotateHandoffs` DEVOLVE MENSAGENS NOVAS: cada linha vira um objeto
     * recriado a cada recomputo. Isso é exatamente o sinal que o `v-memo` da
     * linha usa como primeira chave — "objeto igual = o store não mexeu" —,
     * então as duas coisas se encaixam sem contrato extra, desde que o `v-for`
     * itere ESTA lista e não `groupedMessages` crua. Iterar a crua deixaria a
     * marcação de handoff sem efeito; iterar esta com um memo que compara por
     * identidade continua correto porque o computed só recalcula quando
     * `groupedMessages` muda.
     */
    groupedMessagesWithHandoff() {
      return this.groupedMessages.map(grupo => ({
        ...grupo,
        messages: annotateHandoffs(grupo.messages),
      }));
    },
    showStatusIndicator() {
      const { status } = this.conversationAttributes;
      const isConversationInPendingStatus = status === 'pending';
      const isLastMessageIncoming =
        this.lastMessage.message_type === MESSAGE_TYPE.INCOMING;
      return (
        this.isAgentTyping ||
        (isConversationInPendingStatus && isLastMessageIncoming)
      );
    },
    mostrarBotaoDescer() {
      return !this.estaNoFim;
    },
    rotuloDescer() {
      return this.$t('A11Y.SCROLL_TO_LATEST');
    },
  },
  watch: {
    allMessagesLoaded() {
      this.previousScrollHeight = 0;
    },
    // ── `updated()` → `watch` (aceite da §C.4) ────────────────────────────────
    //
    // O hook `updated()` roda a CADA rerender do componente, por qualquer
    // motivo, e lá dentro havia um `if` comparando tamanhos para adivinhar se a
    // conversa tinha mudado. Um watcher no tamanho diz a mesma coisa sem
    // adivinhação e sem rodar em rerender que não veio de mensagem nova.
    //
    // E é aqui que mora o aceite do bloco: a decisão de rolar passa a depender
    // de ONDE o visitante está. Antes, `scrollToBottom()` era incondicional —
    // chegou mensagem enquanto você lia o histórico, você era arrancado para o
    // fim.
    conversationSize(tamanhoNovo, tamanhoAnterior) {
      this.previousConversationSize = tamanhoNovo;
      const chegaram = Math.max(0, tamanhoNovo - (tamanhoAnterior || 0));
      if (this.estaNoFim) {
        this.$nextTick(() => this.irParaOFim());
        return;
      }
      this.naoLidasAbaixo += chegaram;
    },
  },
  mounted() {
    this.$refs.rolagem?.addEventListener('scroll', this.aoRolar, {
      passive: true,
    });
    this.previousConversationSize = this.conversationSize;
    this.irParaOFim();
  },
  unmounted() {
    this.$refs.rolagem?.removeEventListener('scroll', this.aoRolar);
    if (this.scrollAgendado) clearTimeout(this.scrollAgendado);
  },
  methods: {
    ...mapActions('conversation', ['fetchOldConversations']),
    // Três estados, não dois — e o terceiro é o que o `+` fazia por omissão.
    // A primeira linha de cada bloco de data não recebe classe nenhuma, porque
    // não havia irmão anterior com quem casar e portanto nenhuma das seis
    // regras se aplicava a ela.
    classeAgrupamento(indiceBloco, mensagem, indice) {
      const info = this.agrupamentoPorBloco[indiceBloco]?.[mensagem.id];
      if (!info || indice === 0) return null;
      return info.continuaGrupo ? 'is-continuacao' : 'is-abertura';
    },
    distanciaDoFim(elemento) {
      return elemento.scrollHeight - elemento.scrollTop - elemento.clientHeight;
    },
    irParaOFim() {
      const elemento = this.$refs.rolagem;
      if (!elemento) return;
      // A conta com `previousScrollHeight` é a PRESERVAÇÃO DE POSIÇÃO ao
      // paginar para trás, e o plano manda não mexer nela (§C.4 item 6): é o
      // pedaço que já estava acima da média do mercado.
      elemento.scrollTop = elemento.scrollHeight - this.previousScrollHeight;
      this.previousScrollHeight = 0;
      this.estaNoFim = true;
      this.naoLidasAbaixo = 0;
    },
    // Chamado pelo botão. Separado de `irParaOFim` porque aqui o movimento é
    // pedido pelo visitante, e movimento pedido pode ser animado — o que o
    // bloco 2.08 liga, e o `prefers-reduced-motion` desliga sem perder o
    // destino.
    descerPeloBotao() {
      const elemento = this.$refs.rolagem;
      if (!elemento) return;
      this.previousScrollHeight = 0;
      elemento.scrollTo({ top: elemento.scrollHeight, behavior: 'smooth' });
      this.estaNoFim = true;
      this.naoLidasAbaixo = 0;
    },
    // O throttle é de borda inicial com cauda: a primeira leitura sai na hora
    // (senão o botão demoraria 100 ms para sumir quando o visitante chega ao
    // fim) e a última fica agendada (senão a leitura final do gesto se perde,
    // que é justamente a que decide se ele parou no fim).
    aoRolar() {
      const agora = Date.now();
      const desde = agora - this.ultimoScrollEm;
      if (desde >= INTERVALO_SCROLL) {
        this.ultimoScrollEm = agora;
        this.processarRolagem();
        return;
      }
      if (this.scrollAgendado) return;
      this.scrollAgendado = setTimeout(() => {
        this.scrollAgendado = null;
        this.ultimoScrollEm = Date.now();
        this.processarRolagem();
      }, INTERVALO_SCROLL - desde);
    },
    processarRolagem() {
      const elemento = this.$refs.rolagem;
      if (!elemento) return;

      this.estaNoFim = this.distanciaDoFim(elemento) <= TOLERANCIA_FIM;
      if (this.estaNoFim) this.naoLidasAbaixo = 0;

      if (
        this.isFetchingList ||
        this.allMessagesLoaded ||
        !this.conversationSize
      ) {
        return;
      }

      if (elemento.scrollTop < GATILHO_PAGINACAO) {
        this.fetchOldConversations({ before: this.earliestMessage.id });
        this.previousScrollHeight = elemento.scrollHeight;
      }
    },
  },
};
</script>

<template>
  <!-- ── Bloco 2.04 — a raiz deixou de ser quem rola ──────────────────────────
       Antes a superfície e a rolagem eram o mesmo elemento, e por isso a
       textura tinha de ser `background-image` (que fica presa à caixa do
       elemento) e o botão "descer" não tinha onde se ancorar sem rolar junto
       com as mensagens. Agora a raiz é a SUPERFÍCIE, estática, e a rolagem
       mora num filho. -->
  <div
    class="conversation--container"
    :class="[
      colorSchemeClass,
      prefersDarkMode
        ? 'conversation-container-dark'
        : 'conversation-container-light',
    ]"
  >
    <!-- `role="log"` marca a região onde chegam mensagens novas, e é o que faz
         o leitor de tela anunciar a resposta do agente sem o visitante ter de
         sair do campo de texto para procurá-la. O papel já implica
         `aria-live="polite"`, então não o repetimos: `polite` espera a pausa da
         fala em vez de interromper, que é o comportamento certo para chat.
         `aria-label` porque uma região precisa de nome para ser navegável. -->
    <div
      ref="rolagem"
      class="conversation-wrap"
      role="log"
      :aria-label="$t('A11Y.CONVERSATION_LOG')"
      :aria-busy="isAgentTyping ? 'true' : 'false'"
      :class="{ 'is-typing': isAgentTyping }"
    >
      <div v-if="isFetchingList" class="message--loader">
        <Spinner />
      </div>
      <div
        v-for="(groupedMessage, indiceBloco) in groupedMessagesWithHandoff"
        :key="groupedMessage.date"
        class="messages-wrap"
      >
        <WDateSeparator :date="groupedMessage.date" />
        <!-- ── A JUNÇÃO DO 2.12 COM O 4.09, e por que o `v-memo` está AQUI ────
             O 4.09 precisa renderizar o marcador de handoff ANTES da mensagem
             que o carrega, o que pede um `<template>` em volta dos dois. O 2.12
             precisa do `v-memo` para não refazer o `md.render` de todas as
             bolhas a cada mudança reativa de fora.

             A armadilha: com o `v-memo` no `ChatMessage` DENTRO do
             `<template v-for>`, ele deixa de estar no elemento do `v-for` e o
             Vue o IGNORA — sem erro, sem aviso, sem nada quebrar. Compilando as
             formas com o compilador do Vue 3.5.12, `_isMemoSame` simplesmente
             não aparece no código gerado. O memo viraria decoração.

             Pôr o `v-memo` no PRÓPRIO `<template v-for>` mantém as duas coisas:
             `_isMemoSame` volta ao código gerado, o marcador continua irmão da
             mensagem, e nenhum nó extra entra no DOM. Que ele está ativo está
             medido em `specs/memoDaLinha.spec.js` — pelo TEMPLATE compilado,
             não pela leitura deste comentário. E não pela contagem de renders
             do filho: essa passa com o `v-memo` removido por completo, porque o
             Vue já não re-renderiza filho de props inalteradas. O memo age uma
             camada antes, no VNode, onde espião nenhum no filho enxerga.

             As três chaves: a mensagem (identidade nova = o store mexeu), a
             classe de agrupamento e o idioma. A mensagem aqui é a ANOTADA por
             `annotateHandoffs`, que também recria o objeto — então a marcação
             de handoff entra na mesma chave, sem contrato extra. -->
        <!-- eslint-disable vue/no-useless-template-attributes -- A regra
             considera INUTIL toda diretiva num `<template>` que não seja
             `v-if`/`v-for`/`v-slot`. Aqui ela erra, e a prova não é textual:
             compilado com o Vue 3.5.12, este template gera `_isMemoSame(` no
             código, e a mesma marcação com o `v-memo` no filho não gera. O
             exame que trava isso é `specs/memoDaLinha.spec.js`. -->
        <!-- eslint-disable vue/valid-v-memo -- A regra guarda o caso real
             (`v-memo` num descendente de `v-for`), mas rastreia só o `v-for`
             MAIS EXTERNO: `vForElement` só é atribuído quando ainda é nulo, e
             depois exige que o `v-memo` esteja nesse elemento. Com `v-for`
             aninhado — blocos de data por fora, linhas por dentro — o de dentro
             nunca passa, embora seja o padrão documentado do Vue. -->
        <template
          v-for="(message, indice) in groupedMessage.messages"
          :key="message.id"
          v-memo="[
            message,
            classeAgrupamento(indiceBloco, message, indice),
            idiomaAtual,
          ]"
        >
          <AiHandoffMark
            v-if="message.handoffMark"
            :kind="message.handoffMark.kind"
          />
          <ChatMessage
            :message="message"
            :classe-agrupamento="
              classeAgrupamento(indiceBloco, message, indice)
            "
          />
        </template>
        <!-- eslint-enable vue/valid-v-memo, vue/no-useless-template-attributes -->
      </div>
      <AgentTypingBubble v-if="showStatusIndicator" />
    </div>

    <!-- O caminho de volta. Ele só existe quando o visitante NÃO está no fim,
         que é exatamente quando a lista deixou de rolar sozinha. -->
    <WScrollToBottom
      v-if="mostrarBotaoDescer"
      class="conversation--descer"
      :label="rotuloDescer"
      :count="naoLidasAbaixo"
      @click="descerPeloBotao"
    >
      <FluentIcon icon="chevron-down" size="16" />
    </WScrollToBottom>
  </div>
</template>

<style scoped lang="scss">
.conversation--container {
  display: flex;
  flex-direction: column;
  flex: 1;
  // A raiz não rola mais — ver o comentário no template. `overflow: hidden`
  // porque a textura é pintada por um `::before` de tamanho total.
  overflow: hidden;
  color-scheme: light dark;
  position: relative;
  background-color: var(--w-surface-sunken);

  // ── A textura, bloco 2.04 ──────────────────────────────────────────────────
  //
  // Eram DOIS PNG de 88.534 B e 96.098 B (o mesmo desenho, um com traço preto
  // sobre branco e outro com traço branco sobre preto), cada um coberto por um
  // véu de `linear-gradient` de `0.85` cravado, com o tile de `400px` cravado
  // ao lado.
  //
  // Vira UMA máscara de 24.354 B. O desenho é o mesmo nos dois temas — o que
  // mudava era a cor —, então a cor saiu do arquivo e virou token
  // (`--w-texture-ink`), e a intensidade saiu do véu e virou `opacity`. Com
  // isso o `forced-colors` do bloco 2.08 desliga a textura numa linha, o que
  // com `background-image` não teria como fazer.
  //
  // `-webkit-mask-*` ao lado do `mask-*` não é excesso: sem prefixo o suporte
  // começa no Chrome 120 e no Safari 15.4; com ele, cobre tudo que roda o
  // widget hoje. São seis linhas para não deixar visitante de Safari antigo
  // com a lista lisa.
  &::before {
    content: '';
    position: absolute;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    background-color: rgb(var(--w-texture-ink));
    opacity: var(--w-texture-opacity);
    -webkit-mask-image: url('/assets/images/chat-spx-texture.webp');
    mask-image: url('/assets/images/chat-spx-texture.webp');
    -webkit-mask-size: var(--w-texture-size);
    mask-size: var(--w-texture-size);
    -webkit-mask-repeat: repeat;
    mask-repeat: repeat;
  }

  &.light-scheme {
    color-scheme: light;
  }

  &.dark-scheme {
    color-scheme: dark;
  }

  > * {
    position: relative;
    z-index: 2;
  }
}

.conversation-wrap {
  flex: 1;
  overflow-y: auto;
  // Padding medido em 32/8/8; a §C.4 pede 16/12/8.
  @apply px-3 pt-4 pb-2;
}

.conversation--descer {
  @apply absolute z-10 ltr:right-3 rtl:left-3 bottom-3;
}

.message--loader {
  text-align: center;
}
</style>
