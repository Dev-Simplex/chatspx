/**
 * PAGINAÇÃO PARA TRÁS — bloco 2.04, aceite 4 da §C.4.
 *
 * ACEITE: *"paginando para trás a posição é preservada — não regredir"*.
 *
 * ── Por que este arquivo existe ──────────────────────────────────────────────
 *
 * `rolagem.spec.js` cobre o ramo `estaNoFim` (mensagem NOVA chegando). Nenhum
 * de seus 10 exemplos entra no ramo `scrollTop < GATILHO_PAGINACAO`, que é
 * onde a preservação de posição mora — e era justamente por isso que a
 * regressão passava verde: `previousScrollHeight` era ESCRITO na paginação e
 * lido só dentro de `irParaOFim()`, chamado apenas quando `estaNoFim` é
 * verdadeiro. No topo da lista `estaNoFim` é falso por definição, então o
 * valor era escrito, nunca lido, e zerado no `irParaOFim` seguinte.
 *
 * Duas consequências, ambas medidas aqui:
 *   1. a posição não voltava — o visitante era jogado para o começo do
 *      histórico que acabara de chegar;
 *   2. as mensagens ANTIGAS entravam no contador de não lidas do botão
 *      "descer", que passava a anunciar mensagem nova que não existe.
 *
 * ── O que é medido, e o que não é ────────────────────────────────────────────
 *
 * jsdom não faz layout. A geometria é DITADA: `clientHeight` fixo e
 * `scrollHeight` DERIVADO do número de mensagens, para que prepender histórico
 * cresça a lista como cresceria no navegador. `scrollTop` é gravável porque é
 * nele que a preservação escreve. O que se mede é a decisão em cima desses
 * números, não o pixel.
 *
 * O harness monta um PAI que passa `grouped-messages` a partir do mesmo getter
 * do store que `Messages.vue` usa. Isso não é capricho: o contador e a posição
 * dependem de o tamanho da conversa e a lista agrupada mudarem na MESMA
 * mutação — um dublê que atualizasse a prop por fora mediria uma ordem de
 * atualização que a produção não tem.
 */
import { mount } from '@vue/test-utils';
import { createStore, mapGetters } from 'vuex';
import { createI18n } from 'vue-i18n';
import { defineComponent, h, ref } from 'vue';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ConversationWrap from '../ConversationWrap.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const ALTURA_VISIVEL = 500;
const ALTURA_LINHA = 50;
// Com 10 mensagens a lista mede 2.000 px; prepender 20 leva a 3.000. O delta de
// 1.000 é o número que a posição preservada tem de devolver.
const ALTURA_BASE = 1500;

const mensagem = id => ({
  id,
  content: `m${id}`,
  created_at: 1700000000 + id,
  message_type: 0,
});

const criarStore = (mensagens, fetchOldConversations, allMessagesLoaded) =>
  createStore({
    modules: {
      appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => mensagens.value[0] || {},
          getLastMessage: () =>
            mensagens.value[mensagens.value.length - 1] || {},
          getAllMessagesLoaded: () => allMessagesLoaded.value,
          getIsFetchingList: () => false,
          getConversationSize: () => mensagens.value.length,
          getIsAgentTyping: () => false,
          // A mesma forma que `getGroupedConversation` publica: um bloco por
          // data, com `messages` dentro. Um único bloco basta — o que se mede
          // aqui é a contagem, não o agrupamento.
          getGroupedConversation: () => [
            { date: '01/01/2026', messages: mensagens.value },
          ],
        },
        actions: { fetchOldConversations },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
    },
  });

// O pai é o `Messages.vue` reduzido ao que importa: a prop sai do getter.
const Pai = defineComponent({
  computed: {
    ...mapGetters({ groupedMessages: 'conversation/getGroupedConversation' }),
  },
  render() {
    return h(ConversationWrap, { groupedMessages: this.groupedMessages });
  },
});

const darGeometria = (elemento, mensagens, scrollTop) => {
  Object.defineProperty(elemento, 'scrollHeight', {
    configurable: true,
    get: () => ALTURA_BASE + mensagens.value.length * ALTURA_LINHA,
  });
  Object.defineProperty(elemento, 'clientHeight', {
    configurable: true,
    get: () => ALTURA_VISIVEL,
  });
  let posicao = scrollTop;
  Object.defineProperty(elemento, 'scrollTop', {
    configurable: true,
    get: () => posicao,
    set: valor => {
      posicao = valor;
    },
  });
  elemento.scrollTo = ({ top }) => {
    posicao = top;
  };
};

const montar = ({ scrollTop = 0, quantidade = 10 } = {}) => {
  const mensagens = ref(
    Array.from({ length: quantidade }, (_, i) => mensagem(100 + i))
  );
  const allMessagesLoaded = ref(false);
  const fetchOldConversations = vi.fn();
  const pai = mount(Pai, {
    attachTo: document.body,
    global: {
      plugins: [
        criarStore(mensagens, fetchOldConversations, allMessagesLoaded),
        i18n,
      ],
      stubs: { ChatMessage: true, WDateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });
  const wrapper = pai.findComponent(ConversationWrap);
  const rolagem = wrapper.vm.$refs.rolagem;
  darGeometria(rolagem, mensagens, scrollTop);
  return {
    pai,
    wrapper,
    rolagem,
    mensagens,
    allMessagesLoaded,
    fetchOldConversations,
  };
};

const rolar = async (pai, rolagem) => {
  rolagem.dispatchEvent(new Event('scroll'));
  await pai.vm.$nextTick();
};

// O histórico chega POR CIMA — é isso que distingue paginação de mensagem
// nova, e é a razão de a posição ter de ser corrigida.
const chegarHistorico = async (pai, mensagens, quantas) => {
  const primeiro = mensagens.value[0].id;
  mensagens.value = [
    ...Array.from({ length: quantas }, (_, i) =>
      mensagem(primeiro - quantas + i)
    ),
    ...mensagens.value,
  ];
  await pai.vm.$nextTick();
  await pai.vm.$nextTick();
};

const chegarMensagemNova = async (pai, mensagens, quantas = 1) => {
  const ultimo = mensagens.value[mensagens.value.length - 1].id;
  mensagens.value = [
    ...mensagens.value,
    ...Array.from({ length: quantas }, (_, i) => mensagem(ultimo + 1 + i)),
  ];
  await pai.vm.$nextTick();
  await pai.vm.$nextTick();
};

describe('2.04 — o ramo scrollTop < 100 dispara a paginação', () => {
  it('no topo, pede o histórico e guarda a altura de antes', async () => {
    const { pai, rolagem, fetchOldConversations, wrapper } = montar({
      scrollTop: 0,
    });

    await rolar(pai, rolagem);

    expect(fetchOldConversations).toHaveBeenCalledTimes(1);
    // A guarda anti-vácuo do arquivo: se este ramo não fosse alcançado,
    // TODAS as asserções de "não inflou o contador" abaixo passariam por
    // ausência de sujeito.
    expect(wrapper.vm.previousScrollHeight).toBe(2000);
    expect(wrapper.vm.estaNoFim).toBe(false);
  });

  it('longe do topo, NÃO pede histórico', async () => {
    const { pai, rolagem, fetchOldConversations } = montar({ scrollTop: 900 });

    await rolar(pai, rolagem);

    expect(fetchOldConversations).not.toHaveBeenCalled();
  });
});

describe('2.04 — paginando para trás a posição é preservada', () => {
  it('20 mensagens antigas: o visitante fica onde estava (0 → 1000)', async () => {
    const { pai, rolagem, mensagens } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);
    expect(rolagem.scrollTop).toBe(0);

    await chegarHistorico(pai, mensagens, 20);

    // 3.000 (altura nova) − 2.000 (altura de antes) = 1.000: exatamente o que
    // entrou por cima. O conteúdo sob a janela é o mesmo de antes da busca.
    expect(rolagem.scrollTop).toBe(1000);
  });

  it('preserva o deslocamento que o visitante já tinha (60 → 1060)', async () => {
    // O gatilho é `scrollTop < 100`, então há até 99 px de rolagem própria em
    // jogo. Voltar para 1.000 aqui seria devolver a posição de OUTRO ponto da
    // lista — perto, mas não onde ele estava.
    const { pai, rolagem, mensagens } = montar({ scrollTop: 60 });
    await rolar(pai, rolagem);

    await chegarHistorico(pai, mensagens, 20);

    expect(rolagem.scrollTop).toBe(1060);
  });

  it('a preservação NÃO mente dizendo que ele voltou ao fim', async () => {
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);

    await chegarHistorico(pai, mensagens, 20);

    // Se `estaNoFim` virasse `true` aqui, o botão "descer" sumiria com o
    // visitante a 1.500 px do fim, e a próxima mensagem de verdade o
    // arrancaria da leitura.
    expect(wrapper.vm.estaNoFim).toBe(false);
  });
});

describe('2.04 — o histórico não entra no contador de não lidas', () => {
  it('20 antigas somam 0 ao contador', async () => {
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);

    await chegarHistorico(pai, mensagens, 20);

    expect(wrapper.vm.naoLidasAbaixo).toBe(0);
    expect(wrapper.findComponent({ name: 'WScrollToBottom' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'WScrollToBottom' }).props('count')
    ).toBe(0);
  });

  // O PAR POSITIVO. Sem ele, o exemplo acima passaria também numa
  // implementação que simplesmente nunca conta nada.
  it('mas 20 mensagens NOVAS, com ele lendo para cima, somam 20', async () => {
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 900 });
    await rolar(pai, rolagem);
    expect(wrapper.vm.estaNoFim).toBe(false);

    await chegarMensagemNova(pai, mensagens, 20);

    expect(wrapper.vm.naoLidasAbaixo).toBe(20);
  });

  it('histórico E uma mensagem nova no mesmo lote: conta 1, não 21 nem 0', async () => {
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);

    const primeiro = mensagens.value[0].id;
    const ultimo = mensagens.value[mensagens.value.length - 1].id;
    mensagens.value = [
      ...Array.from({ length: 20 }, (_, i) => mensagem(primeiro - 20 + i)),
      ...mensagens.value,
      mensagem(ultimo + 1),
    ];
    await pai.vm.$nextTick();
    await pai.vm.$nextTick();

    expect(wrapper.vm.naoLidasAbaixo).toBe(1);
  });

  it('mensagem nova ANTES de a busca voltar: conta 1 e a busca segue em voo', async () => {
    // A rede não é ordenada. Entre pedir o histórico e ele chegar, o agente
    // pode responder. Se essa chegada zerasse a paginação em voo, o histórico
    // chegaria depois sem ninguém para corrigir a posição — que é a mesma
    // regressão por outro caminho.
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);

    await chegarMensagemNova(pai, mensagens, 1);
    expect(wrapper.vm.naoLidasAbaixo).toBe(1);
    expect(wrapper.vm.previousScrollHeight).toBe(2000);
    expect(rolagem.scrollTop).toBe(0);

    // E o histórico, chegando depois, ainda preserva. A altura de antes é
    // 2.000 e a de agora é 3.050 (31 linhas), então a correção é 1.050: os
    // 1.000 do histórico MAIS os 50 da mensagem que entrou embaixo — porque a
    // conta é sobre `scrollHeight`, que cresceu pelas duas pontas.
    await chegarHistorico(pai, mensagens, 20);
    expect(wrapper.vm.naoLidasAbaixo).toBe(1);
    expect(rolagem.scrollTop).toBe(1050);
  });

  it('marco perdido: assume histórico em vez de inflar o contador', async () => {
    // Ramo patológico FORÇADO: a mensagem mais antiga conhecida some da lista
    // (o store a substituiu por outra identidade). Sem marco não há como
    // separar o que veio de cima do que veio de baixo, e a escolha é
    // deliberada: um crachá que conta a menos é recuperável — a próxima
    // chegada conta —, um que anuncia 20 mensagens novas inexistentes não.
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 0 });
    await rolar(pai, rolagem);

    const restantes = mensagens.value.slice(1);
    mensagens.value = [
      ...Array.from({ length: 21 }, (_, i) => mensagem(50 + i)),
      ...restantes,
    ];
    await pai.vm.$nextTick();
    await pai.vm.$nextTick();

    expect(wrapper.vm.naoLidasAbaixo).toBe(0);
    expect(rolagem.scrollTop).toBe(1000);
  });
});

describe('2.04 — a paginação não sequestra os outros ramos', () => {
  it('com o visitante no fim, mensagem nova continua rolando', async () => {
    // Conversa curta: com `clientHeight` 1.950 numa lista de 2.000, `scrollTop`
    // 0 está DENTRO do gatilho de paginação (< 100) E dentro da tolerância do
    // fim (2.000 − 0 − 1.950 = 50 ≤ 80). Os dois ramos ficam verdadeiros ao
    // mesmo tempo, e o destino certo é o fim: senão a mensagem que acabou de
    // chegar nasce fora da tela.
    const { pai, rolagem, mensagens, wrapper } = montar({
      scrollTop: 0,
      quantidade: 10,
    });
    Object.defineProperty(rolagem, 'clientHeight', {
      configurable: true,
      get: () => 1950,
    });
    await rolar(pai, rolagem);
    expect(wrapper.vm.estaNoFim).toBe(true);
    // A paginação FOI armada — é isso que torna este exemplo um exame de
    // verdade e não uma repetição do `rolagem.spec.js`.
    expect(wrapper.vm.previousScrollHeight).toBe(2000);

    await chegarMensagemNova(pai, mensagens, 1);

    // A asserção é em distância, não no número cru: o navegador limita
    // `scrollTop` a `scrollHeight − clientHeight` (aqui 100), e o dublê não
    // limita. O que importa é que o destino escrito alcança o fim REAL. Antes
    // da correção o valor era 50 — `scrollHeight − previousScrollHeight` —, que
    // é meia tela acima do fim, com a mensagem nova cortada.
    const fundoReal = rolagem.scrollHeight - rolagem.clientHeight;
    expect(fundoReal).toBe(100);
    expect(rolagem.scrollTop).toBeGreaterThanOrEqual(fundoReal);
    expect(wrapper.vm.naoLidasAbaixo).toBe(0);
  });

  it('sem paginação em voo, o contador segue contando', async () => {
    const { pai, rolagem, mensagens, wrapper } = montar({ scrollTop: 900 });
    await rolar(pai, rolagem);

    await chegarMensagemNova(pai, mensagens, 3);
    expect(wrapper.vm.naoLidasAbaixo).toBe(3);

    await chegarMensagemNova(pai, mensagens, 2);
    expect(wrapper.vm.naoLidasAbaixo).toBe(5);
  });

  it('`allMessagesLoaded` descarta a paginação em voo', async () => {
    const { pai, rolagem, mensagens, allMessagesLoaded, wrapper } = montar({
      scrollTop: 900,
    });
    await rolar(pai, rolagem);
    wrapper.vm.previousScrollHeight = 2000;

    allMessagesLoaded.value = true;
    await pai.vm.$nextTick();
    expect(wrapper.vm.previousScrollHeight).toBe(0);

    // E o que chegar depois volta a ser mensagem nova para o contador.
    await chegarMensagemNova(pai, mensagens, 2);
    expect(wrapper.vm.naoLidasAbaixo).toBe(2);
  });
});
