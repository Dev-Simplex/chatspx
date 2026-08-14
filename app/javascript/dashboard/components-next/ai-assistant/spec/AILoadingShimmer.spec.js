import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

import AILoadingShimmer from '../AILoadingShimmer.vue';

describe('AILoadingShimmer — carregando no padrão OpenAI', () => {
  it('renderiza três pontinhos, nunca um spinner ou barra colorida', () => {
    const wrapper = mount(AILoadingShimmer);
    expect(wrapper.findAll('[data-testid="ai-loading-dot"]')).toHaveLength(3);
    expect(wrapper.findAll('.oa-dot')).toHaveLength(3);

    const html = wrapper.html();
    expect(html).not.toContain('animate-spin');
    expect(html).not.toContain('animate-shimmer');
    expect(html).not.toContain('purple');
  });

  it('escalona a animação dos pontos 2 e 3', () => {
    const wrapper = mount(AILoadingShimmer);
    expect(wrapper.find('.oa-dot--2').exists()).toBe(true);
    expect(wrapper.find('.oa-dot--3').exists()).toBe(true);
  });

  it('não desenha bolha: a resposta que vem depois também não tem', () => {
    const wrapper = mount(AILoadingShimmer);
    const cls = wrapper.find('[data-testid="ai-loading-shimmer"]').classes();
    expect(cls).not.toContain('rounded-2xl');
    expect(cls).not.toContain('shadow-sm');
    expect(cls).toContain('w-full');
  });

  it('expõe role=status e aria-busy=true', () => {
    const wrapper = mount(AILoadingShimmer);
    const root = wrapper.find('[role="status"]');
    expect(root.exists()).toBe(true);
    expect(root.attributes('aria-busy')).toBe('true');
  });

  it('usa a chave i18n como rótulo padrão', () => {
    const wrapper = mount(AILoadingShimmer);
    expect(wrapper.find('[role="status"]').attributes('aria-label')).toBe(
      'CONVERSATION.AI_ASSISTANT_PANEL.LOADING'
    );
    expect(wrapper.text()).toContain('CONVERSATION.AI_ASSISTANT_PANEL.LOADING');
  });

  it('aceita um rótulo do que está sendo feito', () => {
    const wrapper = mount(AILoadingShimmer, {
      props: { label: 'consultando o pedido' },
    });
    expect(wrapper.text()).toContain('consultando o pedido');
    expect(wrapper.find('[role="status"]').attributes('aria-label')).toBe(
      'consultando o pedido'
    );
  });

  it('marca os pontos como aria-hidden — quem fala é o rótulo', () => {
    const wrapper = mount(AILoadingShimmer);
    const dotsWrapper = wrapper.find('[data-testid="ai-loading-dot"]').element
      .parentElement;
    expect(dotsWrapper.getAttribute('aria-hidden')).toBe('true');
  });
});
