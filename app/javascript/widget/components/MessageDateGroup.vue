<script>
import ChatMessage from 'widget/components/ChatMessage.vue';
import AiHandoffMark from 'widget/components/AiHandoffMark.vue';
import WDateSeparator from 'widget/ui/WDateSeparator.vue';
import { calcularAgrupamento } from 'widget/composables/useMessageGrouping';

/**
 * UM bloco de data da conversa — o separador e as linhas daquele dia.
 *
 * ── BLOCO 2.12 — POR QUE ISTO É UM COMPONENTE, E NÃO UM `<div>` NO PAI ───────
 *
 * Este arquivo existe por uma razão só, e ela é medida: **o `v-memo` só tem uma
 * casa de cache por laço, por instância**. É o que `renderList` faz no runtime
 * do Vue (3.5.12, `renderList(source, renderItem, cache, index)`):
 *
 *     const cached = cache && cache[index];   // lê a casa
 *     ...
 *     if (cache) { cache[index] = ret }       // e escreve por cima
 *
 * `cache` é o `renderCache` da INSTÂNCIA e `index` é um número que o compilador
 * crava — para o laço das linhas, `0`. Enquanto os dois laços (blocos de data
 * por fora, linhas por dentro) moravam na MESMA render function de
 * `ConversationWrap`, o laço interno rodava uma vez por bloco e todos disputavam
 * `_cache[0]`: cada bloco lia o que o bloco anterior tinha deixado lá.
 *
 * O efeito não é sutil e não avisa. Com um bloco de data só — conversa que não
 * atravessou a meia-noite — o laço lê o próprio cache e o memo acerta, que é por
 * que o defeito sobreviveu a um bloco dado por feito. A partir do 2º bloco o
 * `_cached.key === message.id` nunca bate (são as mensagens de OUTRO dia), o
 * memo erra 100% das vezes e toda a lista é reconstruída a cada rerender do pai
 * — inclusive o "agente digitando", que pisca o tempo todo. Medido, com o
 * instrumento de identidade de VNode em `specs/memoDaLinha.spec.js`: 2 blocos
 * refaziam 4 linhas de 4; 3 blocos, 6 de 6.
 *
 * Cada instância de componente tem o SEU `renderCache`. Um componente por bloco
 * de data dá a cada laço a sua casa, e o número vai a 0 refeitas nos três casos.
 *
 * A alternativa que o plano também admitia era achatar o `v-for` com o separador
 * como item da lista. Ela resolveria o cache do mesmo jeito, mas custaria a
 * `<div class="messages-wrap">` por dia — que não é decoração: `_conversation.scss`
 * a usa em `&.is-typing .messages-wrap div:last-child`, e o agrupamento visual
 * dos balões é calculado POR BLOCO justamente porque a primeira linha de um dia
 * não continua o grupo do dia anterior.
 *
 * ── O QUE VEIO JUNTO ─────────────────────────────────────────────────────────
 *
 * `calcularAgrupamento` desceu para cá com o laço. No pai ele era um computed
 * sobre TODOS os blocos, então mensagem nova em qualquer dia recalculava o
 * agrupamento de todos os dias; aqui cada bloco só recalcula o próprio. A
 * semântica é a mesma — o cálculo sempre foi por bloco.
 */
export default {
  name: 'MessageDateGroup',
  components: { ChatMessage, AiHandoffMark, WDateSeparator },
  props: {
    date: {
      type: [String, Date, Number],
      required: true,
    },
    /**
     * As mensagens do dia, JÁ anotadas por `annotateHandoffs` (bloco 4.09). A
     * anotação continua no pai porque handoff é uma transição sobre a conversa,
     * e um bloco não enxerga quem falou no dia anterior.
     */
    messages: {
      type: Array,
      default: () => [],
    },
  },
  computed: {
    agrupamento() {
      return calcularAgrupamento(this.messages);
    },
    // ── Bloco 2.12 — a terceira chave do `v-memo` ────────────────────────────
    // As duas primeiras (a mensagem e a classe de agrupamento) cobrem o que muda
    // a linha. Esta cobre o que muda o TEXTO da linha sem mudar a mensagem: o
    // visitante trocando de idioma numa inbox com mais de um habilitado. Sem
    // ela, `RETRY`, `DOWNLOAD` e os rótulos de anexo ficariam no idioma antigo
    // até a mensagem se mexer — que pode ser nunca.
    idiomaAtual() {
      return this.$root.$i18n?.locale;
    },
  },
  methods: {
    // Três estados, não dois — e o terceiro é o que o `+` do CSS antigo fazia
    // por omissão. A primeira linha de cada bloco de data não recebe classe
    // nenhuma, porque não havia irmão anterior com quem casar e portanto
    // nenhuma das seis regras se aplicava a ela.
    classeAgrupamento(mensagem, indice) {
      const info = this.agrupamento[mensagem.id];
      if (!info || indice === 0) return null;
      return info.continuaGrupo ? 'is-continuacao' : 'is-abertura';
    },
  },
};
</script>

<template>
  <div class="messages-wrap">
    <WDateSeparator :date="date" />
    <!-- ── A JUNÇÃO DO 2.12 COM O 4.09, e por que o `v-memo` está AQUI ───────
         O 4.09 precisa renderizar o marcador de handoff ANTES da mensagem que o
         carrega, o que pede um `<template>` em volta dos dois. O 2.12 precisa do
         `v-memo` para não refazer o `md.render` de todas as bolhas a cada
         mudança reativa de fora.

         A armadilha: com o `v-memo` no `ChatMessage` DENTRO do
         `<template v-for>`, ele deixa de estar no elemento do `v-for` e o Vue o
         IGNORA — sem erro, sem aviso, sem nada quebrar. Compilando as formas com
         o compilador do Vue 3.5.12, `_isMemoSame` simplesmente não aparece no
         código gerado. O memo viraria decoração.

         Pôr o `v-memo` no PRÓPRIO `<template v-for>` mantém as duas coisas:
         `_isMemoSame` volta ao código gerado, o marcador continua irmão da
         mensagem, e nenhum nó extra entra no DOM. Que ele está ativo está medido
         em `specs/memoDaLinha.spec.js` — pelo TEMPLATE compilado, não pela
         leitura deste comentário. E não pela contagem de renders do filho: essa
         passa com o `v-memo` removido por completo, porque o Vue já não
         re-renderiza filho de props inalteradas. O memo age uma camada antes, no
         VNode, onde espião nenhum no filho enxerga.

         As três chaves: a mensagem (identidade nova = o store mexeu), a classe
         de agrupamento e o idioma. A mensagem aqui é a ANOTADA por
         `annotateHandoffs`, que também recria o objeto — então a marcação de
         handoff entra na mesma chave, sem contrato extra. -->
    <!-- eslint-disable vue/no-useless-template-attributes -- A regra considera
         INÚTIL toda diretiva num `<template>` que não seja `v-if`/`v-for`/
         `v-slot`. Aqui ela erra, e a prova não é textual: compilado com o Vue
         3.5.12, este template gera `_isMemoSame(` no código, e a mesma marcação
         com o `v-memo` no filho não gera. O exame que trava isso é
         `specs/memoDaLinha.spec.js`. -->
    <template
      v-for="(message, indice) in messages"
      :key="message.id"
      v-memo="[message, classeAgrupamento(message, indice), idiomaAtual]"
    >
      <AiHandoffMark
        v-if="message.handoffMark"
        :kind="message.handoffMark.kind"
      />
      <ChatMessage
        :message="message"
        :classe-agrupamento="classeAgrupamento(message, indice)"
      />
    </template>
    <!-- eslint-enable vue/no-useless-template-attributes -->
  </div>
</template>
