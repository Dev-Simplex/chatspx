import { mount } from '@vue/test-utils';
import WIconButton from '../WIconButton.vue';

describe('WIconButton', () => {
  const montar = (props = {}) =>
    mount(WIconButton, {
      props: { label: 'Fechar o chat', ...props },
      slots: { default: '<svg />' },
    });

  it('o rótulo é obrigatório — é a trava contra o controle mudo', () => {
    expect(WIconButton.props.label.required).toBe(true);
  });

  it('vira nome acessível E dica visual', () => {
    const el = montar({ label: 'Anexar arquivo' });

    expect(el.attributes('aria-label')).toBe('Anexar arquivo');
    expect(el.attributes('title')).toBe('Anexar arquivo');
  });

  it('nasce type="button"', () => {
    expect(montar().attributes('type')).toBe('button');
  });

  it('o tamanho md tem alvo de toque de 44px (classe w-11 h-11)', () => {
    // 44×44 é o mínimo da §C do plano; em jsdom a classe é o que dá para
    // afirmar — o valor computado é verificado em Chromium no 2.03.
    expect(montar({ size: 'md' }).classes()).toContain('w-icon-button--md');
  });

  it('tamanho sm existe para barra densa', () => {
    expect(montar({ size: 'sm' }).classes()).toContain('w-icon-button--sm');
  });

  it('size inválido é recusado pelo validator', () => {
    expect(WIconButton.props.size.validator('gigante')).toBe(false);
  });

  it('desenha o ícone do slot', () => {
    expect(montar().find('svg').exists()).toBe(true);
  });
});
