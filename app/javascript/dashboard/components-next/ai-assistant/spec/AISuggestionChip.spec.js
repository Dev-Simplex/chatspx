import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';

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

import AISuggestionChip from '../AISuggestionChip.vue';

describe('AISuggestionChip', () => {
  beforeEach(() => {
    mockReducedMotion.value = false;
  });

  it('renders the header, subtitle, body and 3 footer actions when not streaming', () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'Olá, posso ajudar?', isStreaming: false },
    });
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT_PANEL.SUGGESTION_CHIP.HEADER'
    );
    expect(wrapper.text()).toContain(
      'AI_ASSISTANT_PANEL.SUGGESTION_CHIP.SUBTITLE'
    );
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-use"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-edit"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-discard"]').exists()
    ).toBe(true);
  });

  it('exposes data-ai-tour="suggestion-chip" anchor for the shepherd tour', () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'hi', isStreaming: false },
    });
    const anchor = wrapper.find('[data-ai-tour="suggestion-chip"]');
    expect(anchor.exists()).toBe(true);
  });

  it('emits accept with the text on Use this one click', async () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'hello', isStreaming: false },
    });
    await wrapper
      .find('[data-testid="ai-suggestion-chip-use"]')
      .trigger('click');
    expect(wrapper.emitted('accept')).toBeTruthy();
    expect(wrapper.emitted('accept')[0][0]).toBe('hello');
  });

  it('emits edit with the text on Editar click', async () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'hello', isStreaming: false },
    });
    await wrapper
      .find('[data-testid="ai-suggestion-chip-edit"]')
      .trigger('click');
    expect(wrapper.emitted('edit')).toBeTruthy();
    expect(wrapper.emitted('edit')[0][0]).toBe('hello');
  });

  it('emits discard on Descartar click', async () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'hello', isStreaming: false },
    });
    await wrapper
      .find('[data-testid="ai-suggestion-chip-discard"]')
      .trigger('click');
    expect(wrapper.emitted('discard')).toBeTruthy();
  });

  it('emits discard on Escape keystroke when not streaming', async () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'hello', isStreaming: false },
      attachTo: document.body,
    });
    // onKeyStroke defaults to listening on window
    const event = new KeyboardEvent('keydown', { key: 'Escape' });
    window.dispatchEvent(event);
    await flushPromises();
    expect(wrapper.emitted('discard')).toBeTruthy();
    wrapper.unmount();
  });

  it('shows the cancel button while streaming and emits cancel-streaming', async () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'streaming...', isStreaming: true },
    });
    const cancel = wrapper.find('[data-testid="ai-suggestion-chip-cancel"]');
    expect(cancel.exists()).toBe(true);
    await cancel.trigger('click');
    expect(wrapper.emitted('cancel-streaming')).toBeTruthy();
    // Footer actions hidden while streaming.
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-use"]').exists()
    ).toBe(false);
  });

  it('renders AIErrorBanner instead of body when errorType is set', () => {
    const wrapper = mount(AISuggestionChip, {
      props: {
        text: 'whatever',
        isStreaming: false,
        errorType: 'rate_limit',
      },
    });
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-error"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-body"]').exists()
    ).toBe(false);
    // Footer actions hidden when in error state.
    expect(
      wrapper.find('[data-testid="ai-suggestion-chip-use"]').exists()
    ).toBe(false);
  });

  it('exposes role=region with header label as aria-label', () => {
    const wrapper = mount(AISuggestionChip, {
      props: { text: 'x', isStreaming: false },
    });
    const anchor = wrapper.find('[data-ai-tour="suggestion-chip"]');
    expect(anchor.attributes('role')).toBe('region');
    expect(anchor.attributes('aria-label')).toBe(
      'AI_ASSISTANT_PANEL.SUGGESTION_CHIP.HEADER'
    );
  });
});
