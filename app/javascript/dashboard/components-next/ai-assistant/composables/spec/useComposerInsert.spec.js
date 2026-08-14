import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';

const h = vi.hoisted(() => ({ chat: null, emitted: [] }));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: (event, payload) => h.emitted.push([event, payload]),
  },
}));

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: () => computed(() => h.chat),
  };
});

import { useComposerInsert } from '../useComposerInsert';

function withComposer() {
  let api = null;
  mount({
    setup() {
      api = useComposerInsert();
      return () => null;
    },
  });
  return api;
}

describe('useComposerInsert', () => {
  beforeEach(() => {
    h.emitted = [];
    h.chat = null;
  });

  it('uses the plain editor bus event for WhatsApp', () => {
    h.chat = { id: 1, meta: { channel: 'Channel::Whatsapp' } };
    const api = withComposer();

    expect(api.insertIntoComposer('texto da IA')).toBe(true);
    expect(h.emitted).toEqual([['insertIntoNormalEditor', 'texto da IA']]);
  });

  it('uses the rich editor bus event for web widget and e-mail', () => {
    h.chat = { id: 1, meta: { channel: 'Channel::WebWidget' } };
    expect(withComposer().insertIntoComposer('oi')).toBe(true);
    expect(h.emitted[0][0]).toBe('insertIntoRichEditor');

    h.emitted = [];
    h.chat = { id: 2, meta: { channel: 'Channel::Email' } };
    withComposer().insertIntoComposer('oi');
    expect(h.emitted[0][0]).toBe('insertIntoRichEditor');
  });

  it('falls back to the inbox channel_type when meta is absent', () => {
    h.chat = { id: 3, inbox: { channel_type: 'Channel::WebWidget' } };
    withComposer().insertIntoComposer('oi');
    expect(h.emitted[0][0]).toBe('insertIntoRichEditor');
  });

  it('refuses to insert empty content', () => {
    h.chat = { id: 1, meta: { channel: 'Channel::Whatsapp' } };
    const api = withComposer();

    expect(api.insertIntoComposer('   ')).toBe(false);
    expect(api.insertIntoComposer('')).toBe(false);
    expect(h.emitted).toEqual([]);
  });

  it('trims the payload before inserting', () => {
    h.chat = { id: 1, meta: { channel: 'Channel::Whatsapp' } };
    withComposer().insertIntoComposer('  com espaços  ');
    expect(h.emitted[0][1]).toBe('com espaços');
  });
});
