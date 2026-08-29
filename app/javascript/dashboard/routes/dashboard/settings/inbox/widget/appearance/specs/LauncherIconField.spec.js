import { mount } from '@vue/test-utils';
import LauncherField from '../LauncherField.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';
import en from 'dashboard/i18n/locale/en/inboxWidget.json';
import { APPEARANCE_LIMITS } from '../../composables/widgetAppearanceContract';

/**
 * Bloco 3.19 — a metade de TELA do ícone do lançador.
 *
 * O SDK já sabia desenhar foto no lançador; a tela não sabia escolher. Não havia
 * controle nenhum de `launcher_icon`, nem upload, nem teto, nem o aviso da
 * decisão D5. O que este spec cobra é exatamente essa metade:
 *
 *   aceite 2 — o aviso sugerindo a foto do time aparece SEMPRE que o modo é
 *              `default`, com a razão escrita, e não oferece banco de imagem;
 *   aceite 3 — imagem acima de 20 KB é recusada, com o motivo, ANTES do upload.
 */
const APARENCIA = {
  position: 'right',
  offset_x: 20,
  offset_y: 20,
  launcher_type: 'standard',
  launcher_text: '',
  hide_bubble: false,
  launcher_icon: 'default',
};

const montar = (appearance = {}, props = {}) =>
  mount(LauncherField, {
    props: { appearance: { ...APARENCIA, ...appearance }, ...props },
  });

const arquivo = (bytes, type = 'image/png') => ({
  name: 'foto.png',
  type,
  size: bytes,
});

/** Dispara o `change` do input de arquivo com o `File` que o navegador daria. */
const escolherArquivo = async (wrapper, file) => {
  const input = wrapper.find('[data-testid="launcher-icon-file"]');
  Object.defineProperty(input.element, 'files', { value: [file] });
  await input.trigger('change');
};

describe('o seletor do ícone do lançador', () => {
  it('oferece os três modos, e `default` é o que vem marcado', () => {
    const wrapper = montar();

    expect(wrapper.find('[data-testid="launcher-icon-default"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="launcher-icon-image"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="launcher-icon-agent_photo"]').exists()
    ).toBe(true);
  });

  it('emite o modo escolhido no formato de string do schema', async () => {
    const wrapper = montar();

    await wrapper
      .find('[data-testid="launcher-icon-agent_photo"]')
      .trigger('click');

    expect(wrapper.emitted('update')).toContainEqual([
      'launcher_icon',
      'agent_photo',
    ]);
  });

  it('lê o modo também na forma `{mode, url}`, que é a que o servidor entrega', () => {
    const wrapper = montar({
      launcher_icon: { mode: 'image', url: 'https://exemplo/a.png' },
    });

    // Se ele lesse só a string, cairia em `default` e mostraria o aviso da D5
    // por cima de uma inbox que JÁ tem foto configurada.
    expect(
      wrapper.find('[data-testid="launcher-icon-suggestion"]').exists()
    ).toBe(false);
    expect(wrapper.find('[data-testid="launcher-icon-file"]').exists()).toBe(
      true
    );
  });
});

describe('o aviso da decisão D5 (aceite 2)', () => {
  it('aparece enquanto o modo é `default`', () => {
    const aviso = montar().find('[data-testid="launcher-icon-suggestion"]');

    expect(aviso.exists()).toBe(true);
    expect(aviso.text()).toContain('converts better');
  });

  it('some quando o lançador já é uma foto — sugestão atendida não se repete', () => {
    expect(
      montar({ launcher_icon: 'agent_photo' })
        .find('[data-testid="launcher-icon-suggestion"]')
        .exists()
    ).toBe(false);
  });

  /**
   * "não oferece banco de imagem" é asserção NEGATIVA, e negativa passa sozinha
   * quando o sujeito nunca existiu. Então o detector é medido primeiro, contra
   * um texto que TEM banco de imagem: se ele não acusar ali, os dois exemplos
   * seguintes não valem nada.
   */
  const OFERECE_BANCO =
    /unsplash|pexels|shutterstock|freepik|getty|banco de imagens?|stock (photo|image)/i;

  it('o detector de banco de imagem acusa quando há um', () => {
    expect(OFERECE_BANCO.test('Não tem foto? Escolha uma no Unsplash.')).toBe(
      true
    );
    expect(OFERECE_BANCO.test('Ou use um banco de imagens gratuito.')).toBe(
      true
    );
  });

  it.each([
    ['pt-BR', ptBR.INBOX_WIDGET.APPEARANCE.LAUNCHER],
    ['en', en.INBOX_WIDGET.APPEARANCE.LAUNCHER],
  ])(
    'em %s o aviso pede foto do time e não oferece banco de imagem',
    (_, l) => {
      expect(OFERECE_BANCO.test(l.ICON_SUGGESTION)).toBe(false);
      // A razão tem de estar escrita: um aviso sem o porquê é só mais uma frase.
      expect(l.ICON_SUGGESTION).toMatch(/converte mais|converts better/);
      expect(l.ICON_SUGGESTION).toMatch(/genérica|generic/);
    }
  );
});

describe('o teto de 20 KB na tela (aceite 3)', () => {
  it('recusa a imagem grande com o motivo, e NÃO chama o upload', async () => {
    const wrapper = montar({ launcher_icon: 'image' });

    await escolherArquivo(
      wrapper,
      arquivo(APPEARANCE_LIMITS.launcherIconMaxBytes + 1)
    );

    const erro = wrapper.find('[data-testid="launcher-icon-error"]');
    expect(erro.exists()).toBe(true);
    expect(erro.text()).toContain('21');
    expect(erro.text()).toContain('20');
    expect(wrapper.emitted('uploadIcon')).toBeUndefined();
  });

  it('recusa formato fora da lista — SVG não entra', async () => {
    const wrapper = montar({ launcher_icon: 'image' });

    await escolherArquivo(wrapper, arquivo(400, 'image/svg+xml'));

    expect(
      wrapper.find('[data-testid="launcher-icon-error"]').text()
    ).toContain('WebP or PNG');
    expect(wrapper.emitted('uploadIcon')).toBeUndefined();
  });

  it('deixa passar a imagem dentro do teto, e aí sim emite o upload', async () => {
    const wrapper = montar({ launcher_icon: 'image' });
    const file = arquivo(APPEARANCE_LIMITS.launcherIconMaxBytes);

    await escolherArquivo(wrapper, file);

    expect(wrapper.emitted('uploadIcon')).toEqual([[file]]);
    expect(wrapper.find('[data-testid="launcher-icon-error"]').exists()).toBe(
      false
    );
  });

  it('avisa que falta imagem enquanto o modo é `image` e não há byte', () => {
    const wrapper = montar({ launcher_icon: 'image' });

    expect(
      wrapper.find('[data-testid="launcher-icon-needs-image"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="launcher-icon-remove"]').exists()).toBe(
      false
    );
  });

  it('com imagem anexada mostra a prévia e o botão de remover', () => {
    const wrapper = montar(
      { launcher_icon: 'image' },
      { launcherIconUrl: 'https://exemplo/rails/blobs/proxy/x/foto.png' }
    );

    expect(
      wrapper.find('[data-testid="launcher-icon-preview"]').attributes('src')
    ).toBe('https://exemplo/rails/blobs/proxy/x/foto.png');

    wrapper.find('[data-testid="launcher-icon-remove"]').trigger('click');
    expect(wrapper.emitted('removeIcon')).toBeTruthy();
  });
});
