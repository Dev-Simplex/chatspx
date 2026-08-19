/**
 * A METADE DE COMPORTAMENTO DO BLOCO 2.12 — o `v-memo` da linha.
 *
 * A outra metade (o construtor de MarkdownIt chamado uma vez) está em
 * `shared/helpers/specs/markdownMemoizacao.spec.js`. As duas atacam o mesmo
 * custo por caminhos diferentes: uma tira o preço de CONSTRUIR o parser, esta
 * tira o de RODAR o render quando nada da linha mudou.
 *
 * O que se mede aqui é o que o `eslint-disable vue/valid-v-memo` em
 * `ConversationWrap.vue` afirma. Um disable de lint sem medição é uma opinião;
 * com estes exemplos ele é um fato verificado, e se o Vue mudar de
 * comportamento o vermelho aparece aqui e não na tela de um cliente.
 *
 * A pergunta que estes exemplos respondem é a única que importa para o memo:
 * **uma mudança reativa FORA da linha refaz a linha?**
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { h, ref } from 'vue';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import { readFileSync } from 'node:fs';
import { parse, compileTemplate } from '@vue/compiler-sfc';
import ConversationWrap from '../ConversationWrap.vue';

const ARQUIVO = 'app/javascript/widget/components/ConversationWrap.vue';

// O template REAL do arquivo, passado pelo compilador real. Comentários fora,
// porque eles não são código — e porque foi por eles que este exame já se
// enganou uma vez.
const compilarTemplate = () => {
  const { descriptor } = parse(readFileSync(ARQUIVO, 'utf8'));
  return compileTemplate({
    source: descriptor.template.content,
    filename: ARQUIVO,
    id: 'memo-da-linha',
    compilerOptions: { comments: false },
  }).code;
};

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

// O dublê conta os próprios renders. Um stub comum (`ChatMessage: true`) não
// serviria: ele renderiza, mas não conta — e a contagem É a medição.
const criarEspiaoDeLinha = () => {
  const renders = { total: 0 };
  const componente = {
    name: 'ChatMessage',
    props: {
      message: { type: Object, default: () => ({}) },
      classeAgrupamento: { type: String, default: null },
    },
    render() {
      renders.total += 1;
      return h('div', { class: 'linha-espia' });
    },
  };
  return { renders, componente };
};

const criarStore = digitando =>
  createStore({
    modules: {
      appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => ({}),
          getLastMessage: () => ({}),
          getAllMessagesLoaded: () => true,
          getIsFetchingList: () => false,
          getConversationSize: () => 0,
          // Reativo de propósito: é este o gatilho de rerender que o memo
          // precisa absorver, e é o mais frequente da tela real — o agente
          // começa e para de digitar o tempo todo.
          getIsAgentTyping: () => digitando.value,
        },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
    },
  });

const mensagens = [
  { id: 1, message_type: 1, content: 'Do agente' },
  { id: 2, message_type: 0, content: 'Do visitante' },
];

const montar = () => {
  const digitando = ref(false);
  const { renders, componente } = criarEspiaoDeLinha();
  const wrapper = mount(ConversationWrap, {
    props: { groupedMessages: [{ date: 'Jan 15, 2025', messages: mensagens }] },
    global: {
      plugins: [criarStore(digitando), i18n],
      stubs: { ChatMessage: componente, WDateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });
  return { wrapper, renders, digitando };
};

describe('2.12 — o `v-memo` da linha', () => {
  // ── O TESTE QUE FALTAVA, e por que os outros três não bastavam ────────────
  //
  // Os três exemplos abaixo continuam válidos, mas nenhum deles MEDE o
  // `v-memo`: medido em 19/08/2026, eles passam com o `v-memo` REMOVIDO por
  // completo. A razão é que o Vue já traz a economia que eles observam — um
  // componente filho cujas props não mudaram não re-renderiza, com memo ou sem
  // (`shouldUpdateComponent`). O espião conta o render do FILHO, e esse render
  // já não acontecia.
  //
  // O `v-memo` age uma camada antes: ele evita CRIAR o VNode e diferenciá-lo,
  // trabalho que é do PAI e que espião nenhum no filho enxerga. Por isso a
  // medição correta é sobre o artefato que roda — a render function compilada.
  //
  // Isto não é preciosismo de teste. É o que separa as duas formas de escrever
  // o mesmo template: com o `v-memo` num descendente do `<template v-for>` em
  // vez de nele próprio, o Vue IGNORA o memo, sem erro e sem aviso, e
  // `_isMemoSame` desaparece do código gerado. Os três exemplos de baixo
  // continuam verdes nessa forma quebrada. Este não.
  //
  // ── E por que a medição é o TEMPLATE COMPILADO, e não `render.toString()` ──
  //
  // A primeira versão deste exemplo lia `ConversationWrap.render.toString()` e
  // procurava `isMemoSame`. Ela passava nas DUAS formas — inclusive na
  // quebrada. O motivo: em dev o Vue preserva os comentários do template dentro
  // da render function, e o comentário que explica a armadilha escreve
  // `_isMemoSame` por extenso. O teste estava lendo a própria documentação e se
  // declarando satisfeito.
  //
  // Compilar o template com `comments: false` tira essa saída: o que sobra é só
  // o código que roda.
  it('o `v-memo` está ATIVO no template compilado', () => {
    const codigo = compilarTemplate();

    expect(
      codigo,
      'o template compilado de ConversationWrap não chama `_isMemoSame` — o ' +
        '`v-memo` foi compilado para nada. A causa quase certa é ele estar ' +
        'num descendente do `v-for` em vez de no próprio elemento que itera: ' +
        'nessa forma o Vue o ignora sem erro e sem aviso.'
    ).toMatch(/_isMemoSame\(/);
  });

  it('mudança fora da linha NÃO refaz a linha', async () => {
    const { wrapper, renders, digitando } = montar();

    expect(renders.total).toBe(2); // as duas mensagens, uma vez cada
    const naMontagem = renders.total;

    digitando.value = true;
    await wrapper.vm.$nextTick();

    // O indicador de digitando entrou na árvore — o pai rerenderizou.
    expect(wrapper.findComponent({ name: 'AgentTypingBubble' }).exists()).toBe(
      true
    );
    // E as bolhas não foram refeitas. ATENÇÃO ao ler esta linha: ela seria
    // verde mesmo sem o memo, porque o Vue já evita re-renderizar filho de
    // props inalteradas. Quem prova o memo é o exemplo do topo; este prova que
    // a linha não é refeita — que é o efeito desejado, por qualquer caminho.
    expect(renders.total).toBe(naMontagem);
  });

  it('mudança NA lista refaz a linha — o memo não pode congelar a conversa', async () => {
    // O risco de todo memo é o oposto do que ele resolve: economizar render a
    // ponto de a tela mentir. `getGroupedConversation` reconstrói cada mensagem
    // quando recomputa, então objeto novo é o sinal de "o store mexeu" — e é
    // essa a chave do memo.
    const { wrapper, renders } = montar();
    const naMontagem = renders.total;

    await wrapper.setProps({
      groupedMessages: [
        {
          date: 'Jan 15, 2025',
          messages: [
            { ...mensagens[0], content: 'Texto editado' },
            { ...mensagens[1] },
          ],
        },
      ],
    });

    expect(renders.total).toBeGreaterThan(naMontagem);
  });

  it('troca de idioma refaz a linha', async () => {
    // A chave que quase ficou de fora. Numa inbox com mais de um idioma o
    // visitante troca em tempo de execução, e os rótulos que a linha desenha
    // (`RETRY`, `DOWNLOAD`, os textos de anexo) vêm do i18n, não da mensagem.
    // Sem esta chave eles ficariam no idioma antigo até a mensagem se mexer —
    // que pode ser nunca.
    const { wrapper, renders } = montar();
    const naMontagem = renders.total;

    i18n.global.locale = 'en';
    await wrapper.vm.$nextTick();

    expect(renders.total).toBeGreaterThan(naMontagem);
    i18n.global.locale = 'pt_BR';
  });
});
