import { mount } from '@vue/test-utils';

import GlowBorder from '../GlowBorder.vue';

describe('GlowBorder', () => {
  it('renders the wrapper with the glow animation class', () => {
    const wrapper = mount(GlowBorder);
    expect(wrapper.find('.glow-border').exists()).toBe(true);
  });

  it('renders slot content inside the wrapper', () => {
    const wrapper = mount(GlowBorder, {
      slots: { default: '<span class="badge-content">3</span>' },
    });
    expect(wrapper.find('.glow-border .badge-content').text()).toBe('3');
  });

  it('defaults to the ruby token as RGB triple CSS var', () => {
    const wrapper = mount(GlowBorder);
    const style = wrapper.attributes('style');
    expect(style).toContain('--glow-border-rgb: var(--ruby-9)');
    expect(style).toContain('--glow-border-duration: 2s');
    expect(style).toContain('--glow-border-radius: inherit');
  });

  it('accepts a token name with the -- prefix', () => {
    const wrapper = mount(GlowBorder, {
      props: { colorToken: '--teal-9' },
    });
    expect(wrapper.attributes('style')).toContain(
      '--glow-border-rgb: var(--teal-9)'
    );
  });

  it('normalizes a token name without the -- prefix', () => {
    const wrapper = mount(GlowBorder, {
      props: { colorToken: 'blue-9' },
    });
    expect(wrapper.attributes('style')).toContain(
      '--glow-border-rgb: var(--blue-9)'
    );
  });

  it('reflects custom duration and radius in CSS vars', () => {
    const wrapper = mount(GlowBorder, {
      props: { duration: 3.5, borderRadius: '9999px' },
    });
    const style = wrapper.attributes('style');
    expect(style).toContain('--glow-border-duration: 3.5s');
    expect(style).toContain('--glow-border-radius: 9999px');
  });

  it('does not use hex colors in the inline style', () => {
    const wrapper = mount(GlowBorder);
    expect(wrapper.attributes('style')).not.toMatch(/#[0-9a-fA-F]{3,8}/);
  });
});
