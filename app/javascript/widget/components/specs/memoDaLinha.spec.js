/**
 * A METADE DE COMPORTAMENTO DO BLOCO 2.12 — o `v-memo` da linha.
 *
 * A outra metade (o construtor de MarkdownIt chamado uma vez) está em
 * `shared/helpers/specs/markdownMemoizacao.spec.js`. As duas atacam o mesmo
 * custo por caminhos diferentes: uma tira o preço de CONSTRUIR o parser, esta
 * tira o de RODAR o render quando nada da linha mudou.
 *
 * O que se mede aqui é o que o `eslint-disable
 * vue/no-useless-template-attributes` em `MessageDateGroup.vue` afirma. Um
 * disable de lint sem medição é uma opinião; com estes exemplos ele é um fato
 * verificado, e se o Vue mudar de comportamento o vermelho aparece aqui e não
 * na tela de um cliente.
 *
 * São DUAS perguntas, e a segunda só apareceu depois:
 *
 *   1. uma mudança reativa FORA da linha refaz a linha?
 *   2. a resposta continua a mesma quando a conversa atravessa a meia-noite e
 *      a lista passa a ter mais de um bloco de data?
 *
 * Até o bloco 2.12 fechar, a resposta era "não" para a primeira e "sim" para a
 * segunda — com o memo errando 100% das vezes a partir do 2º bloco, em
 * silêncio. O porquê está no describe do fim do arquivo.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { h, ref } from 'vue';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import { readFileSync } from 'node:fs';
import { parse, compileTemplate } from '@vue/compiler-sfc';
import ConversationWrap from '../ConversationWrap.vue';

const RAIZ = 'app/javascript/widget/components/';
// Quem desenha a lista: o pai que itera os blocos de data e o filho que itera
// as linhas de um dia. O `v-memo` mora no segundo desde o bloco 2.12.
const ARQUIVO_LISTA = `${RAIZ}ConversationWrap.vue`;
const ARQUIVO_LINHA = `${RAIZ}MessageDateGroup.vue`;

// O template REAL do arquivo, passado pelo compilador real. Comentários fora,
// porque eles não são código — e porque foi por eles que este exame já se
// enganou uma vez.
const compilarTemplate = arquivo => {
  const { descriptor } = parse(readFileSync(arquivo, 'utf8'));
  return compileTemplate({
    source: descriptor.template.content,
    filename: arquivo,
    id: 'memo-da-linha',
    compilerOptions: { comments: false },
  }).code;
};

/**
 * Cada chamada de `_renderList(` do código gerado, com o intervalo que ela
 * ocupa — do abre-parênteses ao fecha correspondente. É com isso que se
 * distingue laço ANINHADO (o defeito) de laço IRMÃO (que não é problema: o
 * compilador dá uma casa de `_cache` a cada um).
 */
const lacosDe = codigo => {
  const MARCA = '_renderList(';
  const lacos = [];
  let de = codigo.indexOf(MARCA);

  while (de !== -1) {
    let profundidade = 0;
    let ate = de + MARCA.length - 1;
    for (; ate < codigo.length; ate += 1) {
      if (codigo[ate] === '(') profundidade += 1;
      if (codigo[ate] === ')') {
        profundidade -= 1;
        if (profundidade === 0) break;
      }
    }
    lacos.push({ de, ate, codigo: codigo.slice(de, ate + 1) });
    de = codigo.indexOf(MARCA, de + MARCA.length);
  }
  return lacos;
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
    const codigo = compilarTemplate(ARQUIVO_LINHA);

    expect(
      codigo,
      'o template compilado de MessageDateGroup não chama `_isMemoSame` — o ' +
        '`v-memo` foi compilado para nada. A causa quase certa é ele estar ' +
        'num descendente do `v-for` em vez de no próprio elemento que itera: ' +
        'nessa forma o Vue o ignora sem erro e sem aviso.'
    ).toMatch(/_isMemoSame\(/);
  });

  // ── A GUARDA ESTRUTURAL DO 2.12 ───────────────────────────────────────────
  //
  // Os exemplos de comportamento mais abaixo medem o efeito; este mede a CAUSA,
  // e é ele que impede a regressão barata — alguém achatar `MessageDateGroup`
  // de volta para dentro de `ConversationWrap` porque "é um `<div>` só".
  //
  // A regra vem do runtime, não de gosto: `renderList(source, renderItem,
  // cache, index)` guarda o resultado do laço em `cache[index]`, e `index` é um
  // número que o compilador crava por laço, por render function. Um laço com
  // memo aninhado DENTRO de outro laço na MESMA render function roda N vezes
  // contra uma casa só — e o memo passa a errar em silêncio a partir da 2ª.
  it('nenhum laço memoizado está aninhado noutro laço na mesma render function', () => {
    [ARQUIVO_LISTA, ARQUIVO_LINHA].forEach(arquivo => {
      const lacos = lacosDe(compilarTemplate(arquivo));
      const memoizados = lacos.filter(laco => laco.codigo.includes('_memo'));
      const aninhados = memoizados.filter(laco =>
        lacos.some(
          outro => outro !== laco && outro.de < laco.de && laco.de < outro.ate
        )
      );

      expect(
        aninhados.length,
        `${arquivo}: um \`v-for\` memoizado está DENTRO de outro \`v-for\` na ` +
          'mesma render function. Os dois disputam a mesma casa de `_cache` e ' +
          'o memo erra em silêncio a partir da 2ª volta do laço externo. A ' +
          'saída é um componente por item do laço externo — que é exatamente ' +
          'por que `MessageDateGroup.vue` existe. Laços IRMÃOS não são ' +
          'problema: o compilador dá uma casa a cada um.'
      ).toBe(0);
    });
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

// ─────────────────────────────────────────────────────────────────────────────
// BLOCO 2.12 — O QUE ACONTECE A PARTIR DO 2º BLOCO DE DATA
//
// Os exemplos acima montam UM grupo. A conversa real atravessa a meia-noite e
// vira dois, três, trinta — e é aí que o `v-memo` deixa de funcionar, em
// silêncio.
//
// A CAUSA, lida no runtime (`renderList` de vue@3.5.12):
//
//     function renderList(source, renderItem, cache, index) {
//       const cached = cache && cache[index];
//       ...
//       if (cache) { cache[index] = ret }
//     }
//
// `cache` é o `renderCache` da INSTÂNCIA e `index` é um número que o compilador
// crava. O template compilado de `ConversationWrap` gerava
// `_renderList(groupedMessage.messages, ..., _cache, 0)` para o laço INTERNO —
// dentro do laço externo dos blocos de data. Ou seja: N blocos, uma casa só.
//
// Cada bloco lia o que o bloco ANTERIOR deixou na casa 0 e escrevia por cima.
// Com dois blocos, o bloco A lê o cache do B e o B lê o do A; as chaves nunca
// batem (`_cached.key === message.id`) e o memo erra 100% das vezes. Com um
// bloco só ele lê o próprio cache e acerta — que é exatamente por que este
// defeito passou despercebido.
//
// ── O INSTRUMENTO ────────────────────────────────────────────────────────────
//
// Contar render do FILHO não mede memo nenhum (é o que o comentário do topo já
// diz). Contar prop também não. O que o memo faz, literalmente, é `return
// _cached` — devolver O MESMO OBJETO VNode. Então a medição é identidade de
// objeto: colhemos os VNodes memoizados da árvore montada (são os únicos com a
// propriedade `.memo`, gravada pelo código compilado), forçamos um rerender e
// perguntamos quais deixaram de ser o mesmo objeto.
//
// Essa medição não depende da forma da correção: vale com o `v-memo` no pai,
// num componente filho por bloco ou num `v-for` achatado.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Colhe os VNodes memoizados da árvore, descendo também para dentro dos
 * componentes filhos — sem isso a medição ficaria cega justamente para a
 * correção que move o laço para um componente por bloco de data.
 */
const colherMemoizados = (vnode, instancia, achados = new Map()) => {
  if (!vnode || typeof vnode !== 'object') return achados;
  if (Array.isArray(vnode)) {
    vnode.forEach(filho => colherMemoizados(filho, instancia, achados));
    return achados;
  }
  if (vnode.memo) achados.set(vnode.key, vnode);
  if (vnode.component) {
    colherMemoizados(vnode.component.subTree, vnode.component, achados);
    return achados;
  }
  if (Array.isArray(vnode.children)) {
    colherMemoizados(vnode.children, instancia, achados);
  }
  return achados;
};

const memoizadosDe = wrapper =>
  colherMemoizados(wrapper.vm.$.subTree, wrapper.vm.$);

/** As instâncias cujo subTree PRÓPRIO contém linha memoizada. */
const donosDoMemo = raiz => {
  const donos = new Set();
  const visitar = (vnode, instancia) => {
    if (!vnode || typeof vnode !== 'object') return;
    if (Array.isArray(vnode)) {
      vnode.forEach(filho => visitar(filho, instancia));
      return;
    }
    if (vnode.memo) donos.add(instancia);
    if (vnode.component) {
      visitar(vnode.component.subTree, vnode.component);
      return;
    }
    if (Array.isArray(vnode.children)) visitar(vnode.children, instancia);
  };
  visitar(raiz.subTree, raiz);
  return [...donos];
};

/** Quantas linhas deixaram de ser o mesmo objeto entre os dois retratos. */
const linhasRefeitas = (antes, depois) => {
  let refeitas = 0;
  antes.forEach((vnode, chave) => {
    if (depois.get(chave) !== vnode) refeitas += 1;
  });
  return refeitas;
};

const blocoDeData = indice => ({
  date: `Jan ${15 + indice}, 2025`,
  messages: [
    { id: indice * 10 + 1, message_type: 1, content: 'Do agente' },
    { id: indice * 10 + 2, message_type: 0, content: 'Do visitante' },
  ],
});

const montarBlocos = quantidade => {
  const digitando = ref(false);
  const { renders, componente } = criarEspiaoDeLinha();
  const wrapper = mount(ConversationWrap, {
    props: {
      groupedMessages: Array.from({ length: quantidade }, (_, indice) =>
        blocoDeData(indice)
      ),
    },
    global: {
      plugins: [criarStore(digitando), i18n],
      stubs: { ChatMessage: componente, WDateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });
  return { wrapper, renders, digitando };
};

describe('2.12 — o memo através de vários blocos de data', () => {
  it('a medição enxerga as linhas memoizadas (senão os números abaixo seriam 0 por vácuo)', () => {
    const { wrapper } = montarBlocos(2);
    const memoizados = memoizadosDe(wrapper);

    expect(
      memoizados.size,
      'nenhum VNode com `.memo` na árvore: ou o `v-memo` sumiu do template, ' +
        'ou o colhedor não está chegando nas linhas. Nos dois casos os ' +
        'exemplos seguintes mediriam o vácuo.'
    ).toBe(4);
    expect(donosDoMemo(wrapper.vm.$).length).toBeGreaterThan(0);
  });

  it('UM bloco: rerender do dono do memo não refaz linha nenhuma (o controle)', async () => {
    // Este é o caso que já funcionava, e é o que torna o exemplo seguinte
    // conclusivo: se ele ficasse vermelho junto, o defeito seria "o memo não
    // funciona", e não "o memo erra a partir do 2º bloco".
    const { wrapper } = montarBlocos(1);
    const antes = memoizadosDe(wrapper);
    // Sem esta linha o exemplo passaria com o `v-memo` REMOVIDO: sem linha
    // memoizada, `antes` fica vazio e "nenhuma foi refeita" vira verdade vazia.
    expect(antes.size).toBe(2);

    donosDoMemo(wrapper.vm.$).forEach(dono => dono.proxy.$forceUpdate());
    await wrapper.vm.$nextTick();

    expect(linhasRefeitas(antes, memoizadosDe(wrapper))).toBe(0);
  });

  it('DOIS blocos: rerender do dono do memo não refaz linha nenhuma', async () => {
    const { wrapper } = montarBlocos(2);
    const antes = memoizadosDe(wrapper);
    expect(antes.size).toBe(4);

    donosDoMemo(wrapper.vm.$).forEach(dono => dono.proxy.$forceUpdate());
    await wrapper.vm.$nextTick();

    expect(
      linhasRefeitas(antes, memoizadosDe(wrapper)),
      'as linhas foram refeitas com o conteúdo intacto. A causa medida é a ' +
        'casa ÚNICA de cache do `renderList`: com o laço das linhas aninhado ' +
        'no laço dos blocos de data, os blocos disputam `_cache[0]`.'
    ).toBe(0);
  });

  it('TRÊS blocos: rerender do dono do memo não refaz linha nenhuma', async () => {
    const { wrapper } = montarBlocos(3);
    const antes = memoizadosDe(wrapper);
    expect(antes.size).toBe(6);

    donosDoMemo(wrapper.vm.$).forEach(dono => dono.proxy.$forceUpdate());
    await wrapper.vm.$nextTick();

    expect(linhasRefeitas(antes, memoizadosDe(wrapper))).toBe(0);
  });

  it('DOIS blocos: mudança reativa FORA da linha não refaz linha nenhuma', async () => {
    // O mesmo aceite do exemplo de um bloco só ("mudança fora da linha NÃO
    // refaz a linha"), agora medido no VNode — que é onde o memo age — e com a
    // conversa atravessando a meia-noite.
    const { wrapper, digitando } = montarBlocos(2);
    const antes = memoizadosDe(wrapper);

    digitando.value = true;
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent({ name: 'AgentTypingBubble' }).exists()).toBe(
      true
    );
    expect(linhasRefeitas(antes, memoizadosDe(wrapper))).toBe(0);
  });
});
