/**
 * A DECISÃO de rolar — bloco 2.04 (§C.4 item 5).
 *
 * ACEITE: *"Mensagem chegando com o visitante 300 px acima não o arranca;
 * chegando com ele no fim, rola; o botão 'descer' aparece com contador;
 * `handleScroll` não executa mais de ~10×/s."*
 *
 * ── O que é medido aqui, e o que NÃO é ───────────────────────────────────────
 *
 * jsdom não tem layout: `scrollHeight`, `clientHeight` e `scrollTop` são zero e
 * ficam zero. Então aqui a geometria é DITADA — os três valores são definidos à
 * mão no elemento — e o que se mede é a DECISÃO tomada em cima deles: rolar ou
 * não, contar ou não, quantas vezes o handler roda.
 *
 * O aceite em pixel de verdade (o visitante 300 px acima, com rolagem real, num
 * navegador real) está em `spec/e2e/widget/scroll.spec.js`. Os dois são
 * necessários: este pega a regra errada, aquele pega a regra certa aplicada ao
 * elemento errado.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
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
const ALTURA_TOTAL = 2000;

const criarStore = (tamanho, fetchOldConversations) =>
  createStore({
    modules: {
      appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => ({ id: 1 }),
          getLastMessage: () => ({}),
          getAllMessagesLoaded: () => false,
          getIsFetchingList: () => false,
          getConversationSize: () => tamanho.value,
          getIsAgentTyping: () => false,
        },
        actions: { fetchOldConversations },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
    },
  });

// A geometria que jsdom não calcula. `scrollTop` precisa ser gravável porque o
// componente escreve nele — é isso que "rolar para o fim" significa.
const darGeometria = (elemento, { scrollTop }) => {
  Object.defineProperty(elemento, 'scrollHeight', {
    configurable: true,
    get: () => ALTURA_TOTAL,
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

const montar = ({
  distanciaDoFim = 0,
  fetchOldConversations = () => {},
} = {}) => {
  const tamanho = ref(4);
  const wrapper = mount(ConversationWrap, {
    props: { groupedMessages: [] },
    attachTo: document.body,
    global: {
      plugins: [criarStore(tamanho, fetchOldConversations), i18n],
      stubs: { ChatMessage: true, WDateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });
  const rolagem = wrapper.vm.$refs.rolagem;
  darGeometria(rolagem, {
    scrollTop: ALTURA_TOTAL - ALTURA_VISIVEL - distanciaDoFim,
  });
  return { wrapper, tamanho, rolagem };
};

const rolar = async (wrapper, rolagem) => {
  rolagem.dispatchEvent(new Event('scroll'));
  await wrapper.vm.$nextTick();
};

describe('2.04 — auto-scroll condicional', () => {
  it('visitante 300 px acima: mensagem nova NÃO o arranca', async () => {
    const { wrapper, tamanho, rolagem } = montar({ distanciaDoFim: 300 });
    await rolar(wrapper, rolagem);
    const antes = rolagem.scrollTop;

    tamanho.value += 1;
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(rolagem.scrollTop).toBe(antes);
  });

  it('visitante no fim: mensagem nova rola', async () => {
    const { wrapper, tamanho, rolagem } = montar({ distanciaDoFim: 0 });
    await rolar(wrapper, rolagem);
    rolagem.scrollTop = 0; // afasta para provar que a rolagem aconteceu

    tamanho.value += 1;
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(rolagem.scrollTop).toBe(ALTURA_TOTAL);
  });

  it('80 px é a tolerância: dentro dela ainda conta como "no fim"', async () => {
    // O número não é estético. Zero seria frágil (o navegador arredonda
    // `scrollTop` em DPR fracionário e uma lista visualmente no fim mede 1 ou
    // 2 px de sobra); 300 devolveria o salto para quem já está lendo histórico.
    const dentro = montar({ distanciaDoFim: 79 });
    await rolar(dentro.wrapper, dentro.rolagem);
    expect(dentro.wrapper.vm.estaNoFim).toBe(true);

    const fora = montar({ distanciaDoFim: 81 });
    await rolar(fora.wrapper, fora.rolagem);
    expect(fora.wrapper.vm.estaNoFim).toBe(false);
  });
});

describe('2.04 — o botão "descer" e o contador', () => {
  it('não existe enquanto o visitante está no fim', async () => {
    const { wrapper, rolagem } = montar({ distanciaDoFim: 0 });
    await rolar(wrapper, rolagem);

    expect(wrapper.findComponent({ name: 'WScrollToBottom' }).exists()).toBe(
      false
    );
  });

  it('aparece quando ele sobe, e conta o que chegou desde então', async () => {
    const { wrapper, tamanho, rolagem } = montar({ distanciaDoFim: 300 });
    await rolar(wrapper, rolagem);

    tamanho.value += 2;
    await wrapper.vm.$nextTick();

    const botao = wrapper.findComponent({ name: 'WScrollToBottom' });
    expect(botao.exists()).toBe(true);
    expect(botao.props('count')).toBe(2);
    // O contador entra no NOME ACESSÍVEL, não só no pixel — senão quem usa
    // leitor de tela ouve "ir para as mensagens mais recentes" e não sabe
    // quantas são.
    expect(botao.text()).toContain('2');
  });

  it('clicar leva ao fim e zera o contador', async () => {
    const { wrapper, tamanho, rolagem } = montar({ distanciaDoFim: 300 });
    await rolar(wrapper, rolagem);
    tamanho.value += 1;
    await wrapper.vm.$nextTick();

    await wrapper.findComponent({ name: 'WScrollToBottom' }).vm.$emit('click');
    await wrapper.vm.$nextTick();

    expect(rolagem.scrollTop).toBe(ALTURA_TOTAL);
    expect(wrapper.vm.naoLidasAbaixo).toBe(0);
    expect(wrapper.findComponent({ name: 'WScrollToBottom' }).exists()).toBe(
      false
    );
  });

  it('voltar ao fim rolando também zera o contador — com a cauda do throttle', async () => {
    const { wrapper, tamanho, rolagem } = montar({ distanciaDoFim: 300 });
    await rolar(wrapper, rolagem);
    tamanho.value += 1;
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.naoLidasAbaixo).toBe(1);

    rolagem.scrollTop = ALTURA_TOTAL - ALTURA_VISIVEL;
    await rolar(wrapper, rolagem);

    // Esta espera não é enfeite de teste: ela É o comportamento. O segundo
    // evento cai dentro da janela de 100 ms do primeiro, então a leitura vai
    // para a CAUDA do throttle em vez de rodar na hora. Sem a cauda o gesto
    // terminaria sem ninguém reler a posição e o botão ficaria preso na tela
    // com o visitante já no fim — que é o defeito que um throttle só de borda
    // inicial produz, e a razão de este ter as duas.
    await new Promise(resolver => {
      setTimeout(resolver, 150);
    });
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.naoLidasAbaixo).toBe(0);
    expect(wrapper.vm.estaNoFim).toBe(true);
  });
});

describe('2.08 — o botão "descer" respeita `prefers-reduced-motion`', () => {
  const original = window.matchMedia;
  afterEach(() => {
    window.matchMedia = original;
  });

  const comPreferencia = valor => {
    window.matchMedia = vi.fn().mockImplementation(consulta => ({
      matches: consulta === '(prefers-reduced-motion: reduce)' ? valor : false,
      media: consulta,
    }));
  };

  // O aceite do 2.08 é "mesmo estado final, sem o percurso". Estes dois
  // exemplos são o par que prova isso: o DESTINO não muda entre eles, só o
  // `behavior`. Um teste que olhasse apenas o `behavior` deixaria passar uma
  // implementação que, com a preferência ligada, não rolasse nada.
  const clicarEDescer = async valor => {
    comPreferencia(valor);
    const { wrapper, rolagem } = montar({ distanciaDoFim: 300 });
    await rolar(wrapper, rolagem);
    const chamadas = [];
    rolagem.scrollTo = opcoes => {
      chamadas.push(opcoes);
      rolagem.scrollTop = opcoes.top;
    };

    wrapper.vm.descerPeloBotao();
    await wrapper.vm.$nextTick();

    return { chamadas, destino: rolagem.scrollTop };
  };

  it('sem a preferência, percorre até o fim', async () => {
    const { chamadas, destino } = await clicarEDescer(false);

    expect(chamadas).toHaveLength(1);
    expect(chamadas[0].behavior).toBe('smooth');
    expect(destino).toBe(ALTURA_TOTAL);
  });

  it('com a preferência, SALTA — e chega no mesmo lugar', async () => {
    const { chamadas, destino } = await clicarEDescer(true);

    expect(chamadas).toHaveLength(1);
    expect(chamadas[0].behavior).toBe('auto');
    // A linha que é o bloco inteiro: o destino é IDÊNTICO ao do caso acima.
    expect(destino).toBe(ALTURA_TOTAL);
  });
});

describe('2.04 — throttle do scroll', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('um gesto contínuo não passa de ~10 execuções por segundo', async () => {
    const { wrapper, rolagem } = montar({ distanciaDoFim: 300 });
    const processar = vi.spyOn(wrapper.vm, 'processarRolagem');

    // 120 eventos em 1 s é o que um scroll contínuo real produz: o navegador
    // dispara `scroll` a cada quadro.
    Array.from({ length: 120 }).forEach(() => {
      rolagem.dispatchEvent(new Event('scroll'));
      vi.advanceTimersByTime(1000 / 120);
    });
    vi.runOnlyPendingTimers();

    expect(processar.mock.calls.length).toBeLessThanOrEqual(11);
    // E não pode ser zero: throttle que engole o gesto inteiro deixaria o botão
    // "descer" preso na tela depois de o visitante já ter voltado ao fim.
    expect(processar.mock.calls.length).toBeGreaterThan(0);
  });
});
