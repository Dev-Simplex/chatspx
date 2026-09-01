<script>
import ChatMessage from 'widget/components/ChatMessage.vue';
import AgentTypingBubble from 'widget/components/AgentTypingBubble.vue';
import WDateSeparator from 'widget/ui/WDateSeparator.vue';
import WScrollToBottom from 'widget/ui/WScrollToBottom.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import ConversationSkeleton from 'widget/components/ConversationSkeleton.vue';
import { useDarkMode } from 'widget/composables/useDarkMode';
import { calcularAgrupamento } from 'widget/composables/useMessageGrouping';
import { comportamentoDeRolagem } from 'widget/composables/useReducedMotion';
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
    ConversationSkeleton,
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
      // ── A paginação em voo, bloco 2.04 ──────────────────────────────────
      //
      // Os três juntos são o retrato de "pedi histórico e ele ainda não
      // voltou". `previousScrollHeight > 0` é o próprio sinal de voo: ele só
      // é escrito no ramo de paginação e só é apagado por
      // `descartarPaginacaoEmVoo`.
      //
      // `previousScrollTop` é novo e não é preciosismo. O gatilho é
      // `scrollTop < 100`, então o visitante pode ter até 99 px de rolagem
      // própria quando a busca sai. A conta antiga
      // (`scrollHeight - previousScrollHeight`) devolvia a posição de quem
      // estava CRAVADO no zero; para os outros, devolvia um ponto vizinho.
      //
      // `idMaisAntigoAntesDaPagina` é o marco que separa o que veio de cima
      // do que veio de baixo quando as duas coisas acontecem no mesmo lote.
      previousScrollHeight: 0,
      previousScrollTop: 0,
      idMaisAntigoAntesDaPagina: null,
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
      this.descartarPaginacaoEmVoo();
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
    // ── O terceiro ramo, bloco 2.04 (§C.4 aceite 4) ─────────────────────────
    //
    // Havia dois: "está no fim, rola" e "não está, conta". Faltava o de quem
    // acabou de PEDIR HISTÓRICO — que por definição não está no fim, e por
    // isso caía no segundo. As mensagens antigas entravam no contador do botão
    // "descer" (20 páginas viravam "20 novas", que não existem) e a posição
    // nunca era corrigida, porque o único leitor de `previousScrollHeight`
    // morava dentro de `irParaOFim`, alcançável só pelo primeiro ramo.
    //
    // A ORDEM importa. `estaNoFim` continua primeiro: numa conversa curta os
    // dois são verdadeiros ao mesmo tempo (`scrollTop` 0 é o topo E o fim), e
    // aí o destino certo é o fim — a mensagem que acabou de chegar tem de
    // estar visível.
    conversationSize(tamanhoNovo, tamanhoAnterior) {
      this.previousConversationSize = tamanhoNovo;
      const chegaram = Math.max(0, tamanhoNovo - (tamanhoAnterior || 0));
      if (this.estaNoFim) {
        this.$nextTick(() => this.irParaOFim());
        return;
      }
      if (this.previousScrollHeight > 0) {
        this.$nextTick(() => this.absorverPaginacao(chegaram));
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
    descartarPaginacaoEmVoo() {
      this.previousScrollHeight = 0;
      this.previousScrollTop = 0;
      this.idMaisAntigoAntesDaPagina = null;
    },
    // A lista crua, achatada. Não é `computed` de propósito: só é lida quando
    // uma paginação volta — uma vez por busca, não uma vez por render.
    mensagensAchatadas() {
      return this.groupedMessages.flatMap(bloco => bloco?.messages || []);
    },
    /**
     * Quantas mensagens entraram POR CIMA — o "delta de paginação" que o
     * aceite manda excluir do contador.
     *
     * O marco é o id que era o mais antigo quando a busca saiu. Tudo o que
     * agora está ANTES dele veio de cima; sua posição na lista É a contagem.
     *
     * Marco não encontrado é o ramo patológico (o store trocou a identidade da
     * mensagem mais antiga). Aí a escolha é assumir que tudo veio de cima, e
     * ela é deliberada: um crachá que conta a menos se corrige na próxima
     * chegada; um que anuncia mensagens novas que não existem, não — e era
     * exatamente esse o defeito.
     */
    quantasVieramDeCima(achatadas, chegaram) {
      const marco = this.idMaisAntigoAntesDaPagina;
      if (marco === null || marco === undefined) return chegaram;
      const posicao = achatadas.findIndex(mensagem => mensagem?.id === marco);
      return posicao === -1 ? chegaram : posicao;
    },
    /**
     * O consumidor de `previousScrollHeight` que faltava — FORA do `estaNoFim`.
     *
     * `deCima === 0` não é "nada chegou": é "o histórico ainda não voltou".
     * Entre pedir e receber, o agente pode responder, e essa resposta entra
     * aqui. Ela conta (veio de baixo) mas NÃO encerra o voo nem mexe na
     * posição — encerrar aqui deixaria o histórico chegar depois sem ninguém
     * para corrigir a rolagem, que é a mesma regressão por outra porta.
     */
    absorverPaginacao(chegaram) {
      const achatadas = this.mensagensAchatadas();
      const deCima = this.quantasVieramDeCima(achatadas, chegaram);
      this.naoLidasAbaixo += Math.max(0, chegaram - deCima);
      if (deCima === 0) return;

      const elemento = this.$refs.rolagem;
      const alturaAntes = this.previousScrollHeight;
      const posicaoAntes = this.previousScrollTop;
      this.descartarPaginacaoEmVoo();
      if (!elemento) return;
      // O conteúdo cresceu por cima: para o visitante continuar vendo as mesmas
      // linhas, `scrollTop` tem de andar exatamente o que a lista cresceu.
      // `estaNoFim` e `naoLidasAbaixo` não se tocam aqui — ele não se moveu.
      elemento.scrollTop = posicaoAntes + (elemento.scrollHeight - alturaAntes);
    },
    irParaOFim() {
      const elemento = this.$refs.rolagem;
      if (!elemento) return;
      // A conta com `previousScrollHeight` SAIU daqui (bloco 2.04). Ela é a
      // preservação de posição ao paginar, e morava no ramo em que a
      // paginação não acontece — de onde nunca rodava. Pior: quando por acaso
      // rodava (conversa curta, em que o topo é também o fim), ela IMPEDIA a
      // ida ao fim, parando `previousScrollHeight` px antes dele. Aqui o
      // destino é o fim, sem exceção; a preservação vive em
      // `absorverPaginacao`.
      elemento.scrollTop = elemento.scrollHeight;
      this.descartarPaginacaoEmVoo();
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
      this.descartarPaginacaoEmVoo();
      // Bloco 2.08. O DESTINO é o mesmo nas duas preferências — o fim da lista,
      // que é o que o visitante pediu ao clicar. O que a preferência muda é só
      // o percurso: `smooth` percorre, `auto` salta. Trocar isto por "não
      // rolar" seria ler `prefers-reduced-motion` como "cancele a ação", e aí o
      // botão simplesmente não funcionaria para quem tem a preferência ligada.
      elemento.scrollTo({
        top: elemento.scrollHeight,
        behavior: comportamentoDeRolagem(),
      });
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
        // O retrato de antes da busca, tirado inteiro num lugar só. Quem o
        // consome é `absorverPaginacao`; quem o descarta é
        // `descartarPaginacaoEmVoo`.
        this.previousScrollHeight = elemento.scrollHeight;
        this.previousScrollTop = elemento.scrollTop;
        this.idMaisAntigoAntesDaPagina = this.earliestMessage?.id ?? null;
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
      <!-- Bloco 2.07 — o esqueleto no lugar do spinner imediato. O `Spinner`
           aparecia no primeiro milissegundo de qualquer busca, inclusive a
           paginação que volta em 80 ms: um flash cinza no topo da lista a cada
           rolagem para trás. Quem segura os 600 ms é `widgetLoadingGate`. -->
      <ConversationSkeleton :loading="isFetchingList" />
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

  // ── `forced-colors` — bloco 2.08 ───────────────────────────────────────────
  //
  // No modo de alto contraste do sistema, o visitante ESCOLHEU um par de cores
  // e o navegador substitui as nossas. A textura não sobrevive a isso de forma
  // útil: a máscara continua recortando, mas a tinta vira uma cor do sistema —
  // o rabisco passa a competir com o texto na mesma cor dele, que é exatamente
  // o ruído que o modo existe para eliminar.
  //
  // Isto é uma linha porque a textura virou máscara no 2.04. Com os dois PNG
  // antigos seria preciso desenhar um terceiro arquivo, ou conviver com o
  // ruído.
  @media (forced-colors: active) {
    &::before {
      display: none;
    }
  }

  // ── `prefers-contrast: more` — bloco 2.08 ──────────────────────────────────
  //
  // Aqui o sistema NÃO troca as cores; quem decide somos nós, e o pedido é
  // "separe mais as coisas". A textura é a primeira a ceder: ela é decoração
  // sobre a superfície onde o texto vive, e reduzir o ruído de fundo aumenta a
  // separação entre o texto e o que está atrás dele sem mexer em cor nenhuma.
  @media (prefers-contrast: more) {
    &::before {
      opacity: 0;
    }
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

  // ── Movimento, bloco 2.08 ──────────────────────────────────────────────────
  //
  // O botão entra quando o visitante sobe e sai quando ele volta ao fim. Sem
  // percurso ele PISCA — aparece e some no meio de um gesto de rolagem, que é o
  // momento em que a tela já está se mexendo. O movimento aqui não é enfeite:
  // ele diz de onde o botão veio (de baixo, que é para onde ele leva).
  animation: conversa-descer-entra 160ms ease-out;
}

@keyframes conversa-descer-entra {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

// ── `prefers-reduced-motion` — bloco 2.08 ────────────────────────────────────
//
// O ESTADO FINAL é o mesmo: o botão visível, opaco, na posição de repouso. O
// que sai é o percurso até ele.
//
// `animation: none` faria isso aqui por acidente — o estado final desta
// animação por acaso coincide com o estado natural do elemento. Mas escrever
// `duration: 0s` é o que continua correto quando a animação NÃO termina no
// estado natural, e é a forma que não vira armadilha para quem editar depois.
// Um teste que só verifica `animation: none` passaria com o botão invisível.
@media (prefers-reduced-motion: reduce) {
  .conversation--descer {
    animation-duration: 0s;
  }
}

.message--loader {
  text-align: center;
}
</style>
