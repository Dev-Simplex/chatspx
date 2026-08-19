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
import ConversationWrap from '../ConversationWrap.vue';

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
    // E as bolhas não foram refeitas. Sem o memo, este número seria 4.
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
