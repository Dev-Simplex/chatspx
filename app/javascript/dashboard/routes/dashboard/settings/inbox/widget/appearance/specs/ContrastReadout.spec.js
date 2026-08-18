import { config, mount } from '@vue/test-utils';
import ContrastReadout from '../ContrastReadout.vue';

const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};
afterEach(() => withLocale('en'));

const build = (color, locale = 'pt_BR') => {
  withLocale(locale);
  return mount(ContrastReadout, { props: { color } });
};

const row = (wrapper, id) => wrapper.find(`[data-testid="contrast-${id}"]`);

describe('ContrastReadout', () => {
  it('exibe 2,27:1 para a marca como texto no claro, e marca como ajustada', () => {
    const wrapper = build('#2dc46f');
    const linha = row(wrapper, 'brandAsTextLight');

    expect(linha.find('[data-testid="ratio"]').text()).toBe('2,27:1');
    expect(linha.find('[data-testid="verdict-adjusted"]').text()).toBe(
      'ajustamos'
    );
    expect(linha.find('[data-testid="adjusted-ratio"]').text()).toContain(
      '5,09:1'
    );
  });

  it('explica o ajuste nominalmente, com as duas cores e os dois números', () => {
    const wrapper = build('#2dc46f');

    expect(wrapper.find('[data-testid="contrast-explanation"]').text()).toBe(
      'Em fundo claro, #2DC46F como texto dá 2,27:1 — abaixo do mínimo ' +
        'legível. Links e rótulos usarão #00802F (5,09:1). O preenchimento ' +
        'continua #2DC46F.'
    );
  });

  it('#009CE0 mostra texto PRETO sobre a marca com 6,83:1, aprovado', () => {
    const wrapper = build('#009ce0');
    const linha = row(wrapper, 'textOnBrand');

    expect(linha.find('[data-testid="ratio"]').text()).toBe('6,83:1');
    expect(linha.find('[data-testid="verdict-pass"]').text()).toBe(
      'passa em AA'
    );
    // o quadradinho ao lado do numero mostra a cor DECIDIDA, e ela e preta
    expect(
      linha
        .find('[data-testid="ratio"]')
        .element.previousElementSibling.getAttribute('style')
    ).toContain('rgb(0, 0, 0)');
  });

  it('mostra os quatro pares, nunca menos', () => {
    const wrapper = build('#2dc46f');

    [
      'textOnBrand',
      'brandAsTextLight',
      'brandAsTextDark',
      'brandAsBorder',
    ].forEach(id => expect(row(wrapper, id).exists()).toBe(true));
  });

  it('em en usa ponto decimal', () => {
    const wrapper = build('#2dc46f', 'en');

    expect(
      row(wrapper, 'brandAsTextLight').find('[data-testid="ratio"]').text()
    ).toBe('2.27:1');
  });

  it('com hex inválido diz que não dá para calcular, em vez de inventar número', () => {
    const wrapper = build('roxo');

    expect(wrapper.text()).toContain('Digite uma cor em hexadecimal');
    expect(wrapper.find('[data-testid="ratio"]').exists()).toBe(false);
  });
});
