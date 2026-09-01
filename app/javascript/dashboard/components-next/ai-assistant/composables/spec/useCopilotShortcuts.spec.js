import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { useCopilotShortcuts } from '../useCopilotShortcuts';

function mountWith(handlers) {
  return mount({
    setup() {
      useCopilotShortcuts(handlers);
      return () => null;
    },
    template: '<div />',
  });
}

function press(key, options = {}, target = window) {
  const event = new KeyboardEvent('keydown', {
    key,
    bubbles: true,
    cancelable: true,
    ...options,
  });
  target.dispatchEvent(event);
  return event;
}

describe('useCopilotShortcuts', () => {
  let handlers;

  beforeEach(() => {
    document.body.innerHTML = '';
    handlers = {
      isOpen: () => true,
      onToggle: vi.fn(),
      onAccept: vi.fn(() => true),
      onDismiss: vi.fn(() => true),
    };
  });

  it('toggles the panel on Ctrl+J and Cmd+J', () => {
    const wrapper = mountWith(handlers);

    press('j', { ctrlKey: true });
    press('J', { metaKey: true });

    expect(handlers.onToggle).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('toggles even when the panel is closed', () => {
    handlers.isOpen = () => false;
    const wrapper = mountWith(handlers);
    press('j', { ctrlKey: true });
    expect(handlers.onToggle).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('accepts with Tab only inside the panel', () => {
    document.body.innerHTML =
      '<div data-ai-panel><button id="inside"></button></div>' +
      '<button id="outside"></button>';
    const wrapper = mountWith(handlers);

    press('Tab', {}, document.getElementById('outside'));
    expect(handlers.onAccept).not.toHaveBeenCalled();

    const consumed = press('Tab', {}, document.getElementById('inside'));
    expect(handlers.onAccept).toHaveBeenCalledTimes(1);
    expect(consumed.defaultPrevented).toBe(true);
    wrapper.unmount();
  });

  it('lets Tab move focus when there is nothing to accept', () => {
    document.body.innerHTML =
      '<div data-ai-panel><button id="i"></button></div>';
    handlers.onAccept = vi.fn(() => false);
    const wrapper = mountWith(handlers);

    const event = press('Tab', {}, document.getElementById('i'));
    expect(handlers.onAccept).toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
    wrapper.unmount();
  });

  it('never hijacks Shift+Tab (backwards focus navigation)', () => {
    document.body.innerHTML =
      '<div data-ai-panel><button id="i"></button></div>';
    const wrapper = mountWith(handlers);

    press('Tab', { shiftKey: true }, document.getElementById('i'));
    expect(handlers.onAccept).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('consumes Esc while there is something to dismiss', () => {
    const wrapper = mountWith(handlers);
    const event = press('Escape');

    expect(handlers.onDismiss).toHaveBeenCalledTimes(1);
    expect(event.defaultPrevented).toBe(true);
    wrapper.unmount();
  });

  it('lets Esc through (closing the dialog) when nothing is dismissible', () => {
    handlers.onDismiss = vi.fn(() => false);
    const wrapper = mountWith(handlers);
    const event = press('Escape');

    expect(event.defaultPrevented).toBe(false);
    wrapper.unmount();
  });

  it('ignores keys while the user is composing (IME)', () => {
    const wrapper = mountWith(handlers);
    const event = new KeyboardEvent('keydown', {
      key: 'j',
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    Object.defineProperty(event, 'isComposing', { value: true });
    window.dispatchEvent(event);

    expect(handlers.onToggle).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('stops listening after unmount', () => {
    const wrapper = mountWith(handlers);
    wrapper.unmount();
    press('j', { ctrlKey: true });
    expect(handlers.onToggle).not.toHaveBeenCalled();
  });
});
