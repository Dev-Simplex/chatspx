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

  const findRoot = wrapper =>
    wrapper.find(
      '[data-testid^="ai-smart-banner"]:not([data-testid$="-cta"]):not([data-testid$="-dismiss"])'
    );

  it('renderiza a variante info com a régua mais fraca para long_thread', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    const root = findRoot(wrapper);
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-l-\[var\(--oa-line\)\]/);
    expect(root.attributes('role')).toBe('status');
    expect(root.attributes('aria-live')).toBe('polite');
  });

  it('renderiza a variante warning com a régua intermediária para sentiment', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.sentiment },
    });
    const root = findRoot(wrapper);
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-l-\[var\(--oa-ink-2\)\]/);
    expect(root.attributes('role')).toBe('status');
  });

  it('renderiza a variante urgent com a régua forte + aria-live assertivo', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.waiting },
    });
    const root = findRoot(wrapper);
    const cls = root.attributes('class') || '';
    expect(cls).toMatch(/border-l-\[var\(--oa-ink\)\]/);
    expect(root.attributes('role')).toBe('alert');
    expect(root.attributes('aria-live')).toBe('assertive');
  });

  it('nenhuma variante usa cor de destaque — a severidade virou peso', () => {
    Object.values(SUGGESTIONS).forEach(suggestion => {
      const html = mount(AISmartBanner, { props: { suggestion } }).html();
      expect(html).not.toMatch(/purple-\d/);
      expect(html).not.toMatch(/amber-\d/);
      expect(html).not.toMatch(/red-\d/);
    });
  });

  it('emits action with the original suggestion on CTA click', async () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    await wrapper.find('[data-testid="ai-smart-banner-cta"]').trigger('click');
    expect(wrapper.emitted('action')).toBeTruthy();
    expect(wrapper.emitted('action')[0][0]).toEqual(SUGGESTIONS.longThread);
  });

  it('emits dismiss on the dismiss link click', async () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.waiting },
    });
    await wrapper
      .find('[data-testid="ai-smart-banner-dismiss"]')
      .trigger('click');
    expect(wrapper.emitted('dismiss')).toBeTruthy();
    expect(wrapper.emitted('dismiss')[0][0]).toEqual(SUGGESTIONS.waiting);
  });

  it('as duas ações moram na mesma régua abaixo do texto — nenhum X solto', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    const cta = wrapper.find('[data-testid="ai-smart-banner-cta"]');
    const dismiss = wrapper.find('[data-testid="ai-smart-banner-dismiss"]');

    // Mesmo pai = mesma linha de base do texto; o X flutuante saiu.
    expect(dismiss.element.parentElement).toBe(cta.element.parentElement);
    expect(dismiss.attributes('class')).not.toContain('absolute');
    expect(findRoot(wrapper).attributes('class')).not.toContain('pr-9');

    // "Dispensar" virou rótulo visível, não só title/aria-label.
    expect(dismiss.text()).toBeTruthy();
  });

  it('dá 44x44 de área clicável às duas ações', () => {
    const wrapper = mount(AISmartBanner, {
      props: { suggestion: SUGGESTIONS.longThread },
    });
    ['cta', 'dismiss'].forEach(action => {
      const button = wrapper.find(`[data-testid="ai-smart-banner-${action}"]`);
      expect(button.attributes('class')).toContain('oa-hit-44');
    });
    // 30px de pílula + 14px de gap = 44 de passo quando a régua quebra.
    const row = wrapper.find('[data-testid="ai-smart-banner-cta"]').element
      .parentElement.className;
    expect(row).toContain('gap-y-3.5');
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
