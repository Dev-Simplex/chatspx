/**
 * Mecanismo de aceite do bloco 2.05 — os 8 aceites da §C.9 do plano 22.
 *
 * Cobertos aqui (jsdom basta): 1 (os dois botões juntos), 2 (enviar desabilitado
 * com campo vazio), 4 (nenhum `keypress`), 5 (IME não envia pela metade) e 7 (as
 * cascas abaixo de 60 linhas).
 *
 * Os aceites 3 (anel de foco não transparente) e 8 (alvos ≥ 44×44 em 375 px) são
 * de CASCADE e CAIXA — moram em `specs/browser/composer-geometry.check.mjs`,
 * porque jsdom não resolve nenhum dos dois.
 *
 * O aceite 6 (foco ao abrir) tem nota própria no relatório: a lógica JÁ existia
 * e o bloco a preserva em vez de reimplementar, como a §C.9 alerta.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ChatInputWrap from '../ChatInputWrap.vue';

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

const montar = () => {
  enviadas.length = 0;
  const store = createStore({
    modules: {
      appConfig: {
        namespaced: true,
        getters: {
          getIsWidgetOpen: () => false,
          getShouldShowEmojiPicker: () => true,
        },
        actions: {},
      },
      conversation: {
        namespaced: true,
        actions: { toggleUserTyping: () => {} },
      },
    },
  });

  return mount(ChatInputWrap, {
    props: { onSendMessage: texto => enviadas.push(texto) },
    global: {
      plugins: [store, i18n],
      stubs: {
        ChatAttachmentButton: true,
        EmojiPicker: true,
        FluentIcon: true,
      },
      directives: { onClickaway: {} },
    },
  });
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
