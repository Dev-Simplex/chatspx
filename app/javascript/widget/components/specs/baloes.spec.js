/**
 * Mecanismo do bloco 2.03 — a METADE DE MARCAÇÃO E ESTRUTURA.
 *
 * A outra metade, que é a que o aceite mede de fato (`boxShadow === 'none'` e
 * contraste ≥ 4,5:1 nos dois temas nas duas cores), é valor COMPUTADO e vive em
 * `specs/browser/bubble-geometry.check.mjs`. jsdom não resolve `var()`, não
 * aplica `@layer` e devolve a string que você escreveu — medir contraste ali
 * seria medir o que eu digitei, não o que o navegador pinta.
 *
 * O que ESTE arquivo trava:
 *
 *   1. As SEIS regras de irmão adjacente que decidiam agrupamento, traduzidas
 *      para a classe que a linha recebe. O composable já foi testado sozinho no
 *      bloco 2.02; aqui o que está sob teste é a LIGAÇÃO — que ele seja
 *      chamado, com a lista certa, e que a classe chegue ao elemento certo.
 *   2. O recorte POR BLOCO DE DATA. É a parte que ninguém veria falhar num
 *      teste do composable e que muda a linha mais visível da lista: a primeira
 *      de cada dia.
 *   3. Que nenhum horário more dentro de um `.chat-bubble` — o "horário fora"
 *      do título do bloco, como invariante de estrutura em vez de pixel.
 *   4. Que `_conversation.scss` não tenha voltado a agrupar por seletor de
 *      irmão adjacente (aceite 6 da §C.4 e aceite 2 do bloco 2.02).
 */
import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ConversationWrap from '../ConversationWrap.vue';
import ImageBubble from '../ImageBubble.vue';
import VideoBubble from '../VideoBubble.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const criarStore = () =>
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
          getIsAgentTyping: () => false,
        },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
    },
  });

const montar = groupedMessages =>
  mount(ConversationWrap, {
    props: { groupedMessages },
    global: {
      plugins: [criarStore(), i18n],
      stubs: { ChatMessage: true, DateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });

// A classe que cada linha recebeu, na ordem em que foram renderizadas.
const classesDasLinhas = wrapper =>
  wrapper
    .findAllComponents({ name: 'ChatMessage' })
    .map(linha => linha.props('classeAgrupamento'));

let proximoId = 100;
// Id novo a cada chamada: `calcularAgrupamento` devolve um mapa `id -> info`, e
// duas mensagens com o mesmo id colapsariam numa entrada só.
const novoId = () => {
  proximoId += 1;
  return proximoId;
};
const agente = (extra = {}) => ({
  id: novoId(),
  message_type: 1,
  content: 'Do agente',
  ...extra,
});
const visitante = (extra = {}) => ({
  id: novoId(),
  message_type: 0,
  content: 'Do visitante',
  ...extra,
});
const umDia = (...mensagens) => [{ date: '15/01/2025', messages: mensagens }];

// Agente que TERMINA com fala do visitante — o antigo `.has-response`.
const agenteComResposta = () =>
  agente({
    content_type: 'input_select',
    content_attributes: { submitted_values: [{ title: 'Suporte' }] },
  });

describe('2.03 · as seis regras do CSS antigo, agora pela ligação', () => {
  // As seis linhas abaixo são, uma a uma, os seis seletores que sumiram de
  // `_conversation.scss`. Se alguma mudar de valor, o espaçamento e o canto
  // quebrado daquela transição mudaram na tela.
  it('agente depois de agente CONTINUA (era `.agent-message-wrap + .agent-message-wrap`)', () => {
    expect(classesDasLinhas(montar(umDia(agente(), agente())))).toEqual([
      null,
      'is-continuacao',
    ]);
  });

  it('visitante depois de agente ABRE (era `.agent-message-wrap + .user-message-wrap`)', () => {
    expect(classesDasLinhas(montar(umDia(agente(), visitante())))).toEqual([
      null,
      'is-abertura',
    ]);
  });

  it('visitante depois de agente COM resposta embutida CONTINUA (era `.has-response + .user-message-wrap`)', () => {
    expect(
      classesDasLinhas(montar(umDia(agenteComResposta(), visitante())))
    ).toEqual([null, 'is-continuacao']);
  });

  it('agente depois de agente COM resposta embutida ABRE (era `.has-response + .agent-message-wrap`)', () => {
    expect(
      classesDasLinhas(montar(umDia(agenteComResposta(), agente())))
    ).toEqual([null, 'is-abertura']);
  });

  it('visitante depois de visitante CONTINUA (era `.user-message-wrap + .user-message-wrap`)', () => {
    expect(classesDasLinhas(montar(umDia(visitante(), visitante())))).toEqual([
      null,
      'is-continuacao',
    ]);
  });

  it('agente depois de visitante ABRE (era `.user-message-wrap + .agent-message-wrap`)', () => {
    expect(classesDasLinhas(montar(umDia(visitante(), agente())))).toEqual([
      null,
      'is-abertura',
    ]);
  });
});

describe('2.03 · o recorte por bloco de data', () => {
  it('a primeira linha de CADA dia não recebe classe nenhuma', () => {
    // O seletor de irmão adjacente nunca casava aqui, porque cada bloco de data
    // é uma `<div>` própria e a linha não tem irmão anterior. Rodando o
    // agrupamento na conversa achatada, esta linha viraria `is-continuacao` e
    // colaria no último balão do dia anterior — atravessando o separador.
    const wrapper = montar([
      { date: '14/01/2025', messages: [agente(), agente()] },
      { date: '15/01/2025', messages: [agente(), visitante()] },
    ]);

    expect(classesDasLinhas(wrapper)).toEqual([
      null,
      'is-continuacao',
      null,
      'is-abertura',
    ]);
  });

  it('lista vazia não quebra e não renderiza linha', () => {
    expect(classesDasLinhas(montar([]))).toEqual([]);
  });
});

describe('2.03 · o horário vive FORA do balão', () => {
  const montarMidia = componente =>
    mount(componente, {
      props: {
        url: 'https://exemplo.test/a.png',
        thumb: 'https://exemplo.test/a.png',
      },
      global: { mocks: { $t: chave => i18n.global.t(chave) } },
    });

  it('ImageBubble não desenha mais horário dentro da mídia', () => {
    const html = montarMidia(ImageBubble).html();

    expect(html).not.toContain('class="time"');
    // O degradê existia só para tornar o horário legível sobre a foto; sem o
    // horário ele escurecia 20% de toda imagem enviada em troca de nada.
    expect(html).not.toContain('::before');
  });

  it('VideoBubble não desenha mais horário sobre a barra de controles', () => {
    expect(montarMidia(VideoBubble).html()).not.toMatch(/whitespace-nowrap/);
  });

  it('nem `ImageBubble` nem `VideoBubble` ainda aceitam `readableTime`', () => {
    // A prop tinha de sumir junto: deixá-la aceita e ignorada é convite para
    // alguém "religar" o horário dentro do balão sem perceber que o bloco 2.03
    // o tirou de lá de propósito.
    expect(ImageBubble.props).not.toHaveProperty('readableTime');
    expect(VideoBubble.props).not.toHaveProperty('readableTime');
  });
});

describe('2.03 · o que não pode voltar ao `_conversation.scss`', () => {
  const SCSS = readFileSync(
    'app/javascript/widget/assets/scss/views/_conversation.scss',
    'utf8'
  );
  // Só as linhas de código: um `+` dentro de comentário é explicação, e é
  // justamente onde os seletores antigos estão documentados.
  const codigo = SCSS.split('\n')
    .filter(linha => !linha.trim().startsWith('//'))
    .join('\n');

  it('nenhum seletor de irmão adjacente entre `*-message-wrap`', () => {
    expect(codigo).not.toMatch(/\+\s*\.(agent|user)-message-wrap/);
  });

  it('nenhum seletor de irmão adjacente entre `chat-bubble-wrap`', () => {
    expect(codigo).not.toMatch(/\+\s*\.chat-bubble-wrap/);
  });

  it('a sombra do balão não voltou', () => {
    expect(codigo).not.toMatch(/rgba\(50,\s*50,\s*93/);
  });

  it('o raio quebrado sai do token, não de literal', () => {
    // 0.25rem era o canto de 4 px em oito declarações. O bloco leva a 6 px, e o
    // valor mora em `--w-bubble-radius-tail`.
    expect(codigo).not.toContain('0.25rem]');
    expect(codigo).toContain('--w-bubble-radius-tail');
  });
});
