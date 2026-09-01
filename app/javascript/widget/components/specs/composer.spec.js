/**
 * Mecanismo de aceite do bloco 2.05 — os 8 aceites da §C.9 do plano 22.
 *
 * Cobertos aqui (jsdom basta): 1 (os dois botões juntos), 2 (enviar desabilitado
 * com campo vazio), 4 (nenhum `keypress`), 5 (IME não envia pela metade), 6 (o
 * foco ao abrir) e 7 (as cascas abaixo de 60 linhas).
 *
 * Os aceites 3 (anel de foco não transparente) e 8 (alvos ≥ 44×44 em 375 px) são
 * de CASCADE e CAIXA — moram em `specs/browser/composer-geometry.check.mjs`,
 * porque jsdom não resolve nenhum dos dois.
 *
 * O aceite 6 ficava sem medição, e a nota antiga aqui dizia que "a lógica JÁ
 * existia". Existia pela metade, e a metade que existia era muda:
 *  · `useComposer.campo` não estava ligado a nó nenhum, e `campo.value?.focus?.()`
 *    engolia a chamada — foco era no-op em TODOS os caminhos;
 *  · o `watch` de `isWidgetOpen` cobre só quem já estava montado quando o widget
 *    abre. O cenário que o aceite nomeia — "abrindo direto na view de mensagens"
 *    — é o oposto: o composer monta com o widget JÁ aberto e nada dispara. O
 *    original tinha um `mounted()` para isso e a reescrita do bloco o perdeu.
 *
 * Por isso os testes de foco exigem `attachTo: document.body`: sem estar no
 * documento, `focus()` não move `document.activeElement` em jsdom e o aceite
 * passaria medindo `<body>` contra `<body>`.
 */
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ChatInputWrap from '../ChatInputWrap.vue';
import ViewWithHeader from '../layouts/ViewWithHeader.vue';

const widgetDir = join(dirname(fileURLToPath(import.meta.url)), '../..');

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

global.chatwootWebChannel = {
  enabledFeatures: ['attachments', 'emoji_picker'],
};

const enviadas = [];

// Wrappers presos ao documento precisam ser desmontados: `document.activeElement`
// é global, e um composer esquecido no `body` faz o teste seguinte medir o foco
// do teste anterior — um verde que não é do sujeito.
const montados = [];
let loja;

afterEach(() => {
  while (montados.length) montados.pop().unmount();
});

const montar = ({ aberto = false, noDocumento = false } = {}) => {
  enviadas.length = 0;
  loja = createStore({
    modules: {
      appConfig: {
        namespaced: true,
        // `state` + `mutations`, e não getter constante: o aceite 6 precisa
        // ABRIR o widget com o composer já montado, que é a única forma de
        // exercitar o `watch` de `isWidgetOpen`.
        state: { aberto },
        getters: {
          getIsWidgetOpen: estado => estado.aberto,
          getShouldShowEmojiPicker: () => true,
        },
        mutations: {
          abrirWidget: estado => {
            estado.aberto = true;
          },
        },
        actions: {},
      },
      conversation: {
        namespaced: true,
        actions: { toggleUserTyping: () => {} },
      },
    },
  });

  const wrapper = mount(ChatInputWrap, {
    props: { onSendMessage: texto => enviadas.push(texto) },
    // Sem estar no documento, `focus()` não move `document.activeElement` em
    // jsdom — o aceite 6 mediria sempre `<body>` e passaria por acidente.
    attachTo: noDocumento ? document.body : undefined,
    global: {
      plugins: [loja, i18n],
      stubs: {
        ChatAttachmentButton: true,
        EmojiPicker: true,
        FluentIcon: true,
      },
      directives: { onClickaway: {} },
    },
  });

  montados.push(wrapper);
  return wrapper;
};

const campo = wrapper => wrapper.find('textarea');
const enviar = wrapper => wrapper.find('[data-testid="composer-send"]');
const anexar = wrapper => wrapper.find('[data-testid="composer-attach"]');

describe('2.05 — aceite 1: enviar E anexar, juntos', () => {
  it('com o campo VAZIO os dois estão na tela', () => {
    const wrapper = montar();

    expect(enviar(wrapper).exists()).toBe(true);
    expect(anexar(wrapper).exists()).toBe(true);
  });

  it('com TEXTO os dois continuam na tela', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('olá');

    expect(enviar(wrapper).exists()).toBe(true);
    expect(anexar(wrapper).exists()).toBe(true);
  });
});

describe('2.05 — aceite 2: enviar desabilitado, nunca ausente', () => {
  it('campo vazio: o botão existe e está desabilitado', () => {
    const wrapper = montar();

    expect(enviar(wrapper).attributes('disabled')).toBeDefined();
  });

  it('só espaço em branco também não habilita', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('    ');

    expect(enviar(wrapper).attributes('disabled')).toBeDefined();
  });

  it('com texto de verdade habilita e envia', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('bom dia');
    expect(enviar(wrapper).attributes('disabled')).toBeUndefined();

    await enviar(wrapper).trigger('click');
    expect(enviadas).toEqual(['bom dia']);
  });

  it('depois de enviar, o campo limpa e o botão volta a desabilitar', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('bom dia');
    await enviar(wrapper).trigger('click');

    expect(campo(wrapper).element.value).toBe('');
    expect(enviar(wrapper).attributes('disabled')).toBeDefined();
  });
});

describe('2.05 — aceite 5: IME não envia pela metade', () => {
  it('Enter durante a composição NÃO envia', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('caf');
    await campo(wrapper).trigger('compositionstart');
    await campo(wrapper).trigger('keydown', { key: 'Enter' });

    expect(enviadas).toEqual([]);
  });

  it('terminada a composição, o mesmo Enter envia', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('café');
    await campo(wrapper).trigger('compositionstart');
    await campo(wrapper).trigger('compositionend');
    await campo(wrapper).trigger('keydown', { key: 'Enter' });

    expect(enviadas).toEqual(['café']);
  });

  it('Shift+Enter não envia — é quebra de linha', async () => {
    const wrapper = montar();

    await campo(wrapper).setValue('linha 1');
    await campo(wrapper).trigger('keydown', { key: 'Enter', shiftKey: true });

    expect(enviadas).toEqual([]);
  });
});

describe('2.05 — aceite 4: nenhum keypress sobra em widget/', () => {
  const arquivos = (dir, acc = []) => {
    readdirSync(dir).forEach(nome => {
      const caminho = join(dir, nome);
      if (statSync(caminho).isDirectory()) {
        if (!['node_modules', 'specs'].includes(nome)) arquivos(caminho, acc);
      } else if (/\.(vue|js)$/.test(nome)) {
        acc.push(caminho);
      }
    });
    return acc;
  };

  it('nenhum listener de keypress — comentários não contam', () => {
    const semComentarios = texto =>
      texto
        .replace(/<!--[\s\S]*?-->/g, '')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/^\s*\/\/.*$/gm, '');

    const culpados = arquivos(widgetDir).filter(caminho =>
      /keypress/.test(semComentarios(readFileSync(caminho, 'utf8')))
    );

    expect(culpados).toEqual([]);
  });
});

describe('2.05 — aceite 6: o foco cai no campo, e não é no-op', () => {
  it('montando com o widget JÁ ABERTO, o foco vai para o textarea', async () => {
    // Este é o cenário exato do aceite: "abrindo direto na view de mensagens".
    // O composer só existe nessa view, então quando ele monta o widget já está
    // aberto e o `watch` de `isWidgetOpen` NUNCA dispara — não houve mudança.
    const wrapper = montar({ aberto: true, noDocumento: true });
    await nextTick();

    expect(document.activeElement).toBe(campo(wrapper).element);
  });

  it('abrindo o widget com o composer montado, o foco vai para o textarea', async () => {
    const wrapper = montar({ aberto: false, noDocumento: true });

    // VERMELHO FORÇADO: antes de abrir, o foco não pode estar no campo — senão
    // a asserção seguinte passaria mesmo com o `watch` morto.
    expect(document.activeElement).not.toBe(campo(wrapper).element);

    loja.commit('appConfig/abrirWidget');
    await nextTick();

    expect(document.activeElement).toBe(campo(wrapper).element);
  });

  it('depois de enviar, o foco VOLTA ao campo', async () => {
    const wrapper = montar({ aberto: true, noDocumento: true });

    await campo(wrapper).setValue('bom dia');
    campo(wrapper).element.blur();
    expect(document.activeElement).not.toBe(campo(wrapper).element);

    await enviar(wrapper).trigger('click');

    expect(document.activeElement).toBe(campo(wrapper).element);
  });

  it('o `campo` do composable aponta para um nó REAL, não para null', () => {
    // O defeito que este bloco fecha era mudo: `campo.value?.focus?.()` com
    // `campo` valendo `null` é um no-op que o optional chaining engole. Sem
    // esta asserção, trocar a ligação por `null` de novo não derrubaria nada
    // além dos testes de foco — e o motivo ficaria ilegível.
    const wrapper = montar({ aberto: true, noDocumento: true });

    expect(wrapper.vm.composer.campo.value).not.toBeNull();
    expect(typeof wrapper.vm.composer.campo.value.focus).toBe('function');
  });
});

describe('2.05 — aceite 6: na tela inicial o foco vai para o h1, não para um campo', () => {
  const lojaDaTela = () =>
    createStore({
      modules: {
        appConfig: {
          namespaced: true,
          state: { aberto: false },
          getters: {
            getAppConfig: () => ({}),
            getIsWidgetOpen: estado => estado.aberto,
            getAvailableMessage: () => 'Estamos conectados',
            getUnavailableMessage: () => 'Estamos ausentes no momento',
            getCanUserEndConversation: () => false,
          },
          mutations: {
            abrirWidget: estado => {
              estado.aberto = true;
            },
          },
        },
        agent: { namespaced: true, getters: { availableAgents: () => [] } },
        conversation: {
          namespaced: true,
          getters: { getConversation: () => ({}) },
        },
        conversationAttributes: {
          namespaced: true,
          getters: { getConversationParams: () => ({ status: 'open' }) },
        },
      },
    });

  const montarTela = rota => {
    const store = lojaDaTela();
    const wrapper = mount(ViewWithHeader, {
      attachTo: document.body,
      global: {
        plugins: [store, i18n],
        stubs: {
          Banner: true,
          Branding: true,
          HeaderActions: true,
          AvailabilityContainer: true,
          FluentIcon: true,
          RouterView: true,
          RouterLink: true,
        },
        mocks: { $route: { name: rota } },
        directives: {
          dompurifyHtml: (el, binding) => {
            el.innerHTML = binding.value;
          },
        },
      },
    });

    montados.push(wrapper);
    return { wrapper, store };
  };

  it('na home, abrir o widget põe o foco no h1 — e não abre teclado', async () => {
    const { wrapper, store } = montarTela('home');

    const h1 = wrapper.find('h1');
    expect(document.activeElement).not.toBe(h1.element);

    store.commit('appConfig/abrirWidget');
    await nextTick();
    await nextTick();

    expect(document.activeElement).toBe(h1.element);
    // O que garante que o teclado virtual não sobe: o alvo do foco não é campo
    // de texto nenhum. Medir "teclado" direto é impossível em jsdom; medir que
    // o foco NÃO caiu num campo editável é o mesmo fato, e é verificável.
    expect(h1.element.tagName).toBe('H1');
    expect(wrapper.find('textarea, input').exists()).toBe(false);
  });

  it('na view de mensagens, a tela NÃO rouba o foco do h1', async () => {
    // O contrapositivo importa: se o cabeçalho puxasse o foco em toda tela,
    // ele brigaria com o composer e o aceite 6 se contradiria.
    const { wrapper, store } = montarTela('messages');

    store.commit('appConfig/abrirWidget');
    await nextTick();
    await nextTick();

    expect(document.activeElement).not.toBe(wrapper.find('h1').element);
  });
});

describe('2.05 — aceite 7: as duas cascas abaixo de 60 linhas', () => {
  it.each([
    ['ChatInputWrap.vue', 60],
    ['ChatFooter.vue', 60],
  ])('%s tem menos de %i linhas', (arquivo, teto) => {
    const linhas = readFileSync(
      join(widgetDir, 'components', arquivo),
      'utf8'
    ).split('\n').length;

    expect(linhas).toBeLessThan(teto);
  });
});
