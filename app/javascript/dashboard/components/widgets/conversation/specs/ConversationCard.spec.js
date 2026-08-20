import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi } from 'vitest';
import ConversationCard from '../ConversationCard.vue';

// lottie-web creates a canvas at import time, which jsdom does not implement —
// it enters the module graph transitively through the dashboard routes.
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const buildStore = () =>
  createStore({
    getters: {
      getSelectedChat: () => ({ id: 999 }),
      getSelectedInbox: () => 0,
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ id: 1 }),
    },
    modules: {
      inboxes: {
        namespaced: true,
        getters: {
          getInboxes: () => [],
          getInbox: () => () => ({}),
        },
      },
      contacts: {
        namespaced: true,
        getters: {
          getContact: () => () => null,
        },
      },
    },
  });

const buildChat = (assignee, overrides = {}) => ({
  id: 1,
  inbox_id: 2,
  status: 'open',
  labels: [],
  meta: {
    assignee,
    sender: { id: 7, name: 'John Doe' },
  },
  ...overrides,
});

const mountCard = (assignee, props = {}, chatOverrides = {}) =>
  shallowMount(ConversationCard, {
    props: { chat: buildChat(assignee, chatOverrides), ...props },
    global: { plugins: [buildStore()] },
  });

describe('ConversationCard — AI assignee chip', () => {
  // Chip consolidado: um único elemento com o sparkle (ícone universal de IA)
  // + o nome da IA, na cor própria do agente. Sem badge "IA" redundante.
  it('renders the AI chip when the assignee is an AI agent (mirror bot)', () => {
    const wrapper = mountCard({ id: 9, name: 'Aria', type: 'agent_bot' });
    const aiChip = wrapper.find('.ai-chip');
    expect(aiChip.exists()).toBe(true);
    expect(aiChip.find('.i-lucide-sparkles').exists()).toBe(true);
    expect(aiChip.text()).toContain('Aria');
  });

  it('renders the AI chip even when showAssignee is false', () => {
    const wrapper = mountCard(
      { id: 9, name: 'Aria', type: 'agent_bot' },
      { showAssignee: false }
    );
    expect(wrapper.find('.ai-chip').exists()).toBe(true);
  });

  it('does not render the AI chip for a human assignee', () => {
    const wrapper = mountCard({ id: 9, name: 'Jane' });
    expect(wrapper.find('.ai-chip').exists()).toBe(false);
  });

  it('does not render the AI chip when there is no assignee', () => {
    const wrapper = mountCard(undefined);
    expect(wrapper.find('.ai-chip').exists()).toBe(false);
  });

  it('uses the sparkles icon (not bot) on the AI chip', () => {
    const wrapper = mountCard(
      { id: 9, name: 'Aria', type: 'agent_bot' },
      { showAssignee: true }
    );
    expect(wrapper.find('.ai-chip .i-lucide-sparkles').exists()).toBe(true);
    expect(wrapper.find('.i-lucide-bot').exists()).toBe(false);
  });

  it('uses the user icon on the assignee name for a human assignee', () => {
    const wrapper = mountCard({ id: 9, name: 'Jane' }, { showAssignee: true });
    const assigneeLabel = wrapper.find('.conversation--assignee');
    expect(assigneeLabel.exists()).toBe(true);
    expect(assigneeLabel.find('.i-lucide-user').exists()).toBe(true);
  });
});

describe('ConversationCard — isUnattendedAndMine guard', () => {
  it('is true for an unattended conversation assigned to the current user', () => {
    const wrapper = mountCard(
      { id: 1, name: 'Jane' },
      {},
      { waiting_since: 1234 }
    );
    expect(wrapper.vm.isUnattendedAndMine).toBe(true);
  });

  it('is false for an AI assignee whose id collides with the current user id', () => {
    // Current user id is 1; a captain mirror bot sharing that id must NOT be
    // counted as "unattended and mine" (User × AgentBot id collision guard).
    const wrapper = mountCard(
      { id: 1, name: 'Aria', type: 'agent_bot' },
      {},
      { waiting_since: 1234 }
    );
    expect(wrapper.vm.isUnattendedAndMine).toBe(false);
  });
});
