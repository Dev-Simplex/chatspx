import { mount } from '@vue/test-utils';
import WButton from '../WButton.vue';
import WSpinner from '../WSpinner.vue';

describe('WButton', () => {
  const montar = (props = {}, slots = { default: 'Enviar' }) =>
    mount(WButton, { props, slots });

  it('nasce type="button", não submit', () => {
    // O default do HTML dentro de <form> é `submit`. É assim que um botão
    // qualquer passa a enviar o formulário sem ninguém ter pedido.
    expect(montar().attributes('type')).toBe('button');
  });

  it('aceita submit quando é isso que se quer', () => {
    expect(montar({ type: 'submit' }).attributes('type')).toBe('submit');
  });

  it('mostra o texto do slot', () => {
    expect(montar().text()).toContain('Enviar');
  });

  it.each([
    ['primary', 'w-button--primary'],
    ['secondary', 'w-button--secondary'],
    ['ghost', 'w-button--ghost'],
  ])('variant %s aplica %s', (variant, classe) => {
    expect(montar({ variant }).classes()).toContain(classe);
  });

  it('carregando: desabilita, marca aria-busy e mostra o spinner com rótulo', () => {
    const el = montar({ loading: true, loadingLabel: 'Enviando mensagem' });

    expect(el.attributes('disabled')).toBeDefined();
    expect(el.attributes('aria-busy')).toBe('true');
    expect(el.findComponent(WSpinner).props('label')).toBe('Enviando mensagem');
  });

  it('sem carregar não há aria-busy nem spinner', () => {
    const el = montar();

    expect(el.attributes('aria-busy')).toBeUndefined();
    expect(el.findComponent(WSpinner).exists()).toBe(false);
  });

  it('disabled desabilita de verdade', () => {
    expect(montar({ disabled: true }).attributes('disabled')).toBeDefined();
  });

  it.each([['variant'], ['size'], ['type']])(
    'a prop %s recusa valor inválido pelo validator',
    prop => {
      expect(WButton.props[prop].validator('nao-existe')).toBe(false);
    }
  );
});
