import { mount } from '@vue/test-utils';
import ThemeModeField from '../ThemeModeField.vue';
import LauncherField from '../LauncherField.vue';

/**
 * Todo `<input type="radio">` desta tela tem nome acessivel.
 *
 * O `RadioCard` do design system renderiza o titulo do cartao num `<h3>` e nao
 * o amarra ao `input`. Sem rotulo, o axe-core reprova com a regra `label`,
 * impacto CRITICAL — foram sete nos nesta tela, nos dois temas, e e' o que o
 * E2E `spec/e2e/appearance/appearance.spec.js:142` pegou em navegador real.
 * Este spec e' a versao rapida daquele: se alguem tirar os `<label for>`, ele
 * fica vermelho em segundos em vez de esperar o Chromium.
 *
 * O que ele NAO faz: afirmar ausencia. Ele exige que exista um `<label>` cujo
 * `for` case com o `id` do input E que tenha texto — um label vazio, ou
 * apontando para id que nao existe, reprova aqui como reprova no axe.
 */
const rotulosDosRadios = wrapper => {
  const inputs = wrapper.findAll('input[type="radio"]');
  expect(inputs.length).toBeGreaterThan(0);

  return inputs.map(input => {
    const id = input.attributes('id');
    const label = wrapper
      .findAll('label')
      .find(l => l.attributes('for') === id);
    return { id, texto: label?.text().trim() ?? null };
  });
};

describe('rotulo acessivel dos cartoes de radio', () => {
  it('os tres modos de tema tem `<label for>` com texto', () => {
    const wrapper = mount(ThemeModeField, { props: { modelValue: 'auto' } });

    const rotulos = rotulosDosRadios(wrapper);

    expect(rotulos.map(r => r.id)).toEqual([
      'theme-light',
      'theme-dark',
      'theme-auto',
    ]);
    rotulos.forEach(({ id, texto }) => {
      expect(texto, `o radio ${id} ficou sem nome acessivel`).toBeTruthy();
    });
  });

  it('posicao e formato do lancador tem `<label for>` com texto', () => {
    const wrapper = mount(LauncherField, {
      props: {
        appearance: {
          position: 'right',
          offset_x: 20,
          offset_y: 20,
          launcher_type: 'standard',
          launcher_text: '',
          hide_bubble: false,
        },
      },
    });

    const rotulos = rotulosDosRadios(wrapper);

    expect(rotulos.map(r => r.id)).toEqual([
      'position-left',
      'position-right',
      'launcher-standard',
      'launcher-expanded_bubble',
    ]);
    rotulos.forEach(({ id, texto }) => {
      expect(texto, `o radio ${id} ficou sem nome acessivel`).toBeTruthy();
    });
  });

  it('o rotulo nao aparece na tela — o texto ja esta no cartao', () => {
    const wrapper = mount(ThemeModeField, { props: { modelValue: 'auto' } });

    const doRadio = wrapper
      .findAll('label')
      .filter(l => l.attributes('for')?.startsWith('theme-'));

    expect(doRadio).toHaveLength(3);
    doRadio.forEach(label => {
      expect(label.classes()).toContain('sr-only');
    });
  });
});
