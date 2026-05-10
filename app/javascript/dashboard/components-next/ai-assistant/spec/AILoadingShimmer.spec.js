import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';
import { mount } from '@vue/test-utils';

// Composable mocks must be hoisted before importing the component under
// test, otherwise the SFC pulls the real implementation at module load.
// `prefersReducedMotion` MUST be a Vue ref so the template's
// `v-if="!prefersReducedMotion"` (with auto-unref via <script setup>)
// reads the boolean value, not the wrapper object.
const mockReducedMotion = ref(false);
vi.mock('dashboard/composables/useReducedMotion', () => ({
  useReducedMotion: () => ({ prefersReducedMotion: mockReducedMotion }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

import AILoadingShimmer from '../AILoadingShimmer.vue';

describe('AILoadingShimmer', () => {
  beforeEach(() => {
    mockReducedMotion.value = false;
  });

  // Helpers -----------------------------------------------------------

  it('renders 3 shimmer bars in the default (non-reduced-motion) variant', () => {
    const wrapper = mount(AILoadingShimmer);
    const bars = wrapper.findAll('.animate-shimmer');
    expect(bars).toHaveLength(3);
  });

  it('shimmer bars use staggered animation-delay arbitrary classes', () => {
    const wrapper = mount(AILoadingShimmer);
    const html = wrapper.html();
    expect(html).toMatch(/\[animation-delay:150ms\]/);
    expect(html).toMatch(/\[animation-delay:300ms\]/);
  });

  it('exposes role=status and aria-busy=true so SR announces loading', () => {
    const wrapper = mount(AILoadingShimmer);
    const root = wrapper.find('[role="status"]');
    expect(root.exists()).toBe(true);
    expect(root.attributes('aria-busy')).toBe('true');
  });

  it('uses i18n key for the aria-label loading copy', () => {
    const wrapper = mount(AILoadingShimmer);
    const root = wrapper.find('[role="status"]');
    expect(root.attributes('aria-label')).toBe(
      'CONVERSATION.AI_ASSISTANT_PANEL.LOADING'
    );
  });

  it('keeps a sr-only label inside the bubble for redundancy', () => {
    const wrapper = mount(AILoadingShimmer);
    const srOnly = wrapper.find('.sr-only');
    expect(srOnly.exists()).toBe(true);
    expect(srOnly.text()).toBe('CONVERSATION.AI_ASSISTANT_PANEL.LOADING');
  });

  it('falls back to 3 pulsing dots when prefers-reduced-motion is on', () => {
    mockReducedMotion.value = true;
    const wrapper = mount(AILoadingShimmer);

    expect(wrapper.findAll('.animate-shimmer')).toHaveLength(0);

    const dots = wrapper.findAll('.animate-pulse');
    expect(dots).toHaveLength(3);
  });

  it('reduced-motion variant still keeps role=status and aria-busy', () => {
    mockReducedMotion.value = true;
    const wrapper = mount(AILoadingShimmer);
    const root = wrapper.find('[role="status"]');
    expect(root.exists()).toBe(true);
    expect(root.attributes('aria-busy')).toBe('true');
  });

  it('marks visual-only elements as aria-hidden so SR is not duplicated', () => {
    const wrapper = mount(AILoadingShimmer);
    const ariaHidden = wrapper.findAll('[aria-hidden="true"]');
    // 3 shimmer bars are aria-hidden in the default variant.
    expect(ariaHidden.length).toBeGreaterThanOrEqual(3);
  });
});
