import { mount } from '@vue/test-utils';

import BorderBeam from '../BorderBeam.vue';

describe('BorderBeam', () => {
  it('renders the beam overlay with the animation class', () => {
    const wrapper = mount(BorderBeam);
    const beam = wrapper.find('.border-beam');
    expect(beam.exists()).toBe(true);
  });

  it('is decorative only: aria-hidden so SR ignores it', () => {
    const wrapper = mount(BorderBeam);
    expect(wrapper.attributes('aria-hidden')).toBe('true');
  });

  it('exposes default props as CSS vars (tokens, never hex)', () => {
    const wrapper = mount(BorderBeam);
    const style = wrapper.attributes('style');
    expect(style).toContain('--border-beam-duration: 6s');
    expect(style).toContain('--border-beam-size: 1.5px');
    expect(style).toContain('--border-beam-color-from: rgb(var(--blue-9))');
    expect(style).toContain('--border-beam-color-to: rgb(var(--iris-9))');
    expect(style).toContain('--border-beam-radius: inherit');
  });

  it('reflects custom props in the CSS vars', () => {
    const wrapper = mount(BorderBeam, {
      props: {
        duration: 10,
        size: 2,
        colorFrom: 'rgb(var(--ruby-9))',
        colorTo: 'rgb(var(--teal-9))',
        borderRadius: '8px',
      },
    });
    const style = wrapper.attributes('style');
    expect(style).toContain('--border-beam-duration: 10s');
    expect(style).toContain('--border-beam-size: 2px');
    expect(style).toContain('--border-beam-color-from: rgb(var(--ruby-9))');
    expect(style).toContain('--border-beam-color-to: rgb(var(--teal-9))');
    expect(style).toContain('--border-beam-radius: 8px');
  });

  it('does not use hex colors in the default props', () => {
    const wrapper = mount(BorderBeam);
    expect(wrapper.attributes('style')).not.toMatch(/#[0-9a-fA-F]{3,8}/);
  });
});
