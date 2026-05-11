import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ref } from 'vue';
import { mount } from '@vue/test-utils';

const mockReducedMotion = ref(false);
vi.mock('dashboard/composables/useReducedMotion', () => ({
  useReducedMotion: () => ({ prefersReducedMotion: mockReducedMotion }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (params && Object.keys(params).length > 0) {
        return `${key}:${JSON.stringify(params)}`;
      }
      return key;
    },
  }),
}));

import AISmartBanner from '../AISmartBanner.vue';

const SUGGESTIONS = {
  longThread: {
    id: 'long_thread',
    severity: 'info',
    icon: 'i-lucide-sparkles',
    textKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.LONG_THREAD.BODY',
    textParams: { count: 23 },
    ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.LONG_THREAD.CTA',
    action: 'summarize',
  },
  sentiment: {
    id: 'sentiment',
    severity: 'warning',
    icon: 'i-lucide-alert-triangle',
    textKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.SENTIMENT.BODY',
    textParams: {},
    ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.SENTIMENT.CTA',
    action: 'reply_suggestion',
  },
  waiting: {
    id: 'waiting',
    severity: 'urgent',
    icon: 'i-lucide-clock',
    textKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.WAITING.BODY',
    textParams: { minutes: 6 },
    ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.WAITING.CTA',
    action: 'reply_suggestion',
  },
};

describe('AISmartBanner', () => {
  beforeEach(() => {
    mockReducedMotion.value = false;
  });

  it('renders the info variant with purple tone classes for long_thread', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    const root = wrapper.find(
      '[data-testid^="ai-smart-banner"]:not([data-testid$="-cta"]):not([data-testid$="-dismiss"])'
    );
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-purple-500/);
    expect(cls).toMatch(/bg-purple-50/);
    expect(root.attributes('role')).toBe('status');
    expect(root.attributes('aria-live')).toBe('polite');
  });

  it('renders the warning variant with amber tone classes for sentiment', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.sentiment },
    });
    const root = wrapper.find(
      '[data-testid^="ai-smart-banner"]:not([data-testid$="-cta"]):not([data-testid$="-dismiss"])'
    );
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-amber-500/);
    expect(cls).toMatch(/bg-amber-50/);
    expect(root.attributes('role')).toBe('status');
  });

  it('renders the urgent variant with red tone + assertive aria-live for waiting', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.waiting },
    });
    const root = wrapper.find(
      '[data-testid^="ai-smart-banner"]:not([data-testid$="-cta"]):not([data-testid$="-dismiss"])'
    );
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-red-500/);
    expect(cls).toMatch(/bg-red-50/);
    expect(root.attributes('role')).toBe('alert');
    expect(root.attributes('aria-live')).toBe('assertive');
  });

  it('emits action with the original suggestion on CTA click', async () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    await wrapper.find('[data-testid="ai-smart-banner-cta"]').trigger('click');
    expect(wrapper.emitted('action')).toBeTruthy();
    expect(wrapper.emitted('action')[0][0]).toEqual(SUGGESTIONS.longThread);
  });

  it('emits dismiss on the X button click', async () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.waiting },
    });
    await wrapper
      .find('[data-testid="ai-smart-banner-dismiss"]')
      .trigger('click');
    expect(wrapper.emitted('dismiss')).toBeTruthy();
    expect(wrapper.emitted('dismiss')[0][0]).toEqual(SUGGESTIONS.waiting);
  });

  it('interpolates textParams into the body via i18n', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    expect(wrapper.text()).toContain('"count":23');
  });

  it('keeps the forced-colors fallback border on the root', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    const root = wrapper.find(
      '[data-testid^="ai-smart-banner"]:not([data-testid$="-cta"]):not([data-testid$="-dismiss"])'
    );
    expect(root.attributes('class')).toMatch(/forced-colors:border-current/);
  });
});
