import { mount } from '@vue/test-utils';
import WSpinner from '../WSpinner.vue';

describe('WSpinner', () => {
  const montar = (props = {}) =>
    mount(WSpinner, { props: { label: 'Carregando', ...props } });

  it('anuncia-se ao leitor de tela com role e o rótulo recebido', () => {
    const el = montar({ label: 'Carregando mensagens' });

    expect(el.attributes('role')).toBe('status');
    expect(el.attributes('aria-label')).toBe('Carregando mensagens');
  });

  it('o rótulo é obrigatório — é o que impede um controle mudo', () => {
    expect(WSpinner.props.label.required).toBe(true);
  });

  it.each([
    ['tiny', 'w-spinner--tiny'],
    ['small', 'w-spinner--small'],
    ['medium', 'w-spinner--medium'],
  ])('size %s aplica a classe %s', (size, classe) => {
    const el = montar({ size });

    expect(el.classes()).toContain('w-spinner');
    expect(el.classes()).toContain(classe);
  });

  it('sem size vira small', () => {
    expect(montar().classes()).toContain('w-spinner--small');
  });

  it('size inválido é recusado pelo validator, não aceito em silêncio', () => {
    const { validator } = WSpinner.props.size;

    expect(validator('small')).toBe(true);
    expect(validator('gigante')).toBe(false);
    expect(validator('')).toBe(false);
  });

  it('atributos do chamador não duplicam no root (inheritAttrs: false)', () => {
    // O root já declara role e aria-label; deixar um `role` de fora entrar por
    // fallthrough daria dois papéis no mesmo elemento.
    const el = mount(WSpinner, {
      props: { label: 'Carregando' },
      attrs: { role: 'progressbar' },
    });

    expect(el.attributes('role')).toBe('status');
  });
});
