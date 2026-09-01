import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';

import AIQuickPromptCard from '../AIQuickPromptCard.vue';

const baseProps = {
  label: 'Resumir esta conversa',
  description: 'o que já foi tratado até aqui',
};

describe('AIQuickPromptCard — cartão do estado vazio', () => {
  it('renderiza rótulo e segunda linha, alinhados à esquerda', () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    expect(wrapper.text()).toContain('Resumir esta conversa');
    expect(wrapper.text()).toContain('o que já foi tratado até aqui');
    expect(wrapper.classes()).toContain('text-left');
  });

  it('usa os tokens --oa-* e nenhum realce colorido', () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    const cls = wrapper.attributes('class');
    expect(cls).toContain('border-[var(--oa-line)]');
    expect(cls).toContain('bg-[var(--oa-bg)]');
    expect(cls).toContain('hover:bg-[var(--oa-hover)]');
    expect(wrapper.html()).not.toMatch(/purple-\d/);
    // Sem "lift": o hover só troca o fundo.
    expect(cls).not.toContain('hover:scale-');
  });

  it('mantém o alvo de toque de 44px', () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    expect(wrapper.attributes('class')).toContain('min-h-[44px]');
  });

  it('restabelece border-style — sem isso o cartão fica invisível', () => {
    // `_base.scss` aplica `border-0 border-none` a TODO <button> do produto e
    // a classe `.border` do Tailwind só define a LARGURA. Sem `border-solid`
    // o cartão computa `border-style: none` e mede 1,00:1 contra o fundo.
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    const cls = wrapper.attributes('class');
    expect(cls).toContain('border-solid');
    expect(cls).toContain('border-[var(--oa-line)]');
  });

  it('separa ação de explicação por peso, não por cor', () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    const [label, description] = wrapper.findAll('span > span');
    expect(label.text()).toBe('Resumir esta conversa');
    expect(label.attributes('class')).toContain('font-medium');
    expect(description.attributes('class')).toContain('text-[var(--oa-ink-2)]');
  });

  it('emite click quando habilitado', async () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    await wrapper.trigger('click');
    expect(wrapper.emitted('click')).toBeTruthy();
  });

  it('não emite click quando desabilitado e expõe o motivo', async () => {
    const wrapper = mount(AIQuickPromptCard, {
      props: {
        ...baseProps,
        disabled: true,
        disabledReason: 'Modo nota privada',
      },
    });
    await wrapper.trigger('click');
    expect(wrapper.emitted('click')).toBeFalsy();
    expect(wrapper.attributes('aria-disabled')).toBe('true');
    expect(wrapper.text()).toContain('Modo nota privada');

    const describedBy = wrapper.attributes('aria-describedby');
    expect(describedBy).toBeTruthy();
    expect(wrapper.find(`#${describedBy}`).text()).toBe('Modo nota privada');
  });

  it('desabilitado não usa opacity — o motivo tem que continuar legível', () => {
    // `opacity` no pai multiplica tudo, inclusive a linha que explica por que o
    // cartão está fora do ar. O estado é dito com tokens, em opacidade cheia.
    const wrapper = mount(AIQuickPromptCard, {
      props: {
        ...baseProps,
        disabled: true,
        disabledReason: 'Modo nota privada',
      },
    });
    const cls = wrapper.attributes('class');
    expect(cls).not.toMatch(/(^|\s|:)opacity-(?!100)\d/);
    // `_base.scss:286` aplica `disabled:opacity-50` a todo <button> do produto:
    // sem desligar a global, tirar a nossa classe não resolve nada.
    expect(cls).toContain('disabled:opacity-100');
    expect(cls).toContain('border-[var(--oa-line-soft)]');
    expect(cls).toContain('bg-[var(--oa-side)]');
    expect(cls).toContain('text-[var(--oa-ink-2)]');
    // e sem hover: o cartão não responde ao mouse quando não pode ser usado
    expect(cls).not.toContain('hover:bg-[var(--oa-hover)]');
  });

  it('aponta aria-describedby para a descrição quando habilitado', () => {
    const wrapper = mount(AIQuickPromptCard, { props: baseProps });
    const describedBy = wrapper.attributes('aria-describedby');
    expect(wrapper.find(`#${describedBy}`).text()).toBe(
      'o que já foi tratado até aqui'
    );
  });

  it('renderiza o ícone monocromático quando informado', () => {
    const wrapper = mount(AIQuickPromptCard, {
      props: { ...baseProps, icon: 'i-lucide-list' },
    });
    const icon = wrapper.find('.i-lucide-list');
    expect(icon.exists()).toBe(true);
    expect(icon.attributes('class')).toContain('text-[var(--oa-ink-2)]');
    expect(icon.attributes('aria-hidden')).toBe('true');
  });
});
