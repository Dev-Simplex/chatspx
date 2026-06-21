import { mount } from '@vue/test-utils';

import AnimatedCheckmark from '../AnimatedCheckmark.vue';

describe('AnimatedCheckmark', () => {
  it('renders an SVG sized by the default prop (24)', () => {
    const wrapper = mount(AnimatedCheckmark);
    const svg = wrapper.find('svg');
    expect(svg.exists()).toBe(true);
    expect(svg.attributes('width')).toBe('24');
    expect(svg.attributes('height')).toBe('24');
  });

  it('respects a custom size prop', () => {
    const wrapper = mount(AnimatedCheckmark, { props: { size: 48 } });
    const svg = wrapper.find('svg');
    expect(svg.attributes('width')).toBe('48');
    expect(svg.attributes('height')).toBe('48');
  });

  it('uses currentColor stroke (dark mode for free, no hex)', () => {
    const wrapper = mount(AnimatedCheckmark);
    const svg = wrapper.find('svg');
    expect(svg.attributes('stroke')).toBe('currentColor');
    expect(svg.attributes('fill')).toBe('none');
    expect(wrapper.html()).not.toMatch(/#[0-9a-fA-F]{3,8}/);
  });

  it('draws circle + check with the stroke-dashoffset animation classes', () => {
    const wrapper = mount(AnimatedCheckmark);
    expect(wrapper.find('circle.checkmark-circle').exists()).toBe(true);
    expect(wrapper.find('path.checkmark-check').exists()).toBe(true);
  });

  it('is decorative only: aria-hidden so SR ignores it', () => {
    const wrapper = mount(AnimatedCheckmark);
    expect(wrapper.find('svg').attributes('aria-hidden')).toBe('true');
  });
});
