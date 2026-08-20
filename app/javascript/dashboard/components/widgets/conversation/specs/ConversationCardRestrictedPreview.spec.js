import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi } from 'vitest';
import ConversationCard from '../ConversationCard.vue';

vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

// Usuário 1, NÃO administrador (accounts vazio) — é para ele que o isolamento por agente vale.
const buildStore = () =>
  createStore({
    getters: {
      getCurrentAccount: () => ({ id: 1 }),
      getCurrentUser: () => ({ id: 1, accounts: [] }),
    },
  });

const RESTRICTED_BODY = 'valor da proposta que o outro agente combinou';

const mountCard = ({ agentId, isolation }) =>
  shallowMount(ConversationCard, {
    props: {
      chat: {
        id: 1,
        labels: [],
        priority: null,
        unread_count: 0,
        timestamp: 1700000000,
        created_at: 1700000000,
        meta: {},
        messages: [
          {
            id: 9,
            content: RESTRICTED_BODY,
            message_type: 1,
            agent_id: agentId,
            created_at: 1700000000,
            private: false,
          },
        ],
      },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
      },
      assignee: {},
      inbox: { id: 1, agent_message_isolation: isolation },
    },
    global: { plugins: [buildStore()] },
  });

const previewOf = wrapper =>
  wrapper.findComponent({ name: 'MessagePreview' }).props('message');

// ChatSPX (A4-5): o merge deixou o preview de mensagem restrita como um 🔒 SOLTO, sem texto — o
// agente vê um cadeado e não sabe se a conversa está vazia ou restrita. A chave já existe e está
// traduzida nos 55 locales. Valor exato, e o texto cru não pode vazar.
describe('ConversationCard — preview de mensagem restrita a outro agente', () => {
  it('masks the preview with the padlock AND the translated label', () => {
    const preview = previewOf(mountCard({ agentId: 42, isolation: true }));

    expect(preview.content).toBe('🔒 Restricted content');
    expect(preview.content).not.toContain(RESTRICTED_BODY);
    expect(preview.attachments).toEqual([]);
    expect(preview.content_type).toBe('text');
  });

  it('does not mask the agent own message', () => {
    const preview = previewOf(mountCard({ agentId: 1, isolation: true }));

    expect(preview.content).toBe(RESTRICTED_BODY);
  });

  it('does not mask anything when the inbox has no agent isolation', () => {
    const preview = previewOf(mountCard({ agentId: 42, isolation: false }));

    expect(preview.content).toBe(RESTRICTED_BODY);
  });
});
