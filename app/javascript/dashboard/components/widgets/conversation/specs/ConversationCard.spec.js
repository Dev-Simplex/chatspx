import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi } from 'vitest';
import ConversationCard from '../ConversationCard.vue';

vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const buildStore = () =>
  createStore({
    getters: {
      getCurrentAccount: () => ({ id: 1 }),
      getCurrentUser: () => ({ id: 1, accounts: [] }),
    },
  });

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
  meta: {},
};

const mountComponent = (
  chat = {},
  currentContact = {},
  assignee = chat.meta?.assignee
) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      assignee: assignee || {},
      inbox: { id: 1 },
    },
    global: { plugins: [buildStore()] },
  });

describe('ConversationCard — AI assignee chip', () => {
  const mountWithAssignee = (assignee, props = {}, chat = {}) =>
    shallowMount(ConversationCard, {
      props: {
        chat: {
          ...defaultChat,
          ...chat,
          meta: { ...(chat.meta || {}), assignee },
        },
        currentContact: {
          name: 'John Doe',
          thumbnail: '',
          availability_status: 'offline',
        },
        inbox: { id: 2 },
        assignee: assignee || {},
        ...props,
      },
      global: { plugins: [buildStore()] },
    });

  it('renders the AI chip when the assignee is an AI agent', () => {
    const wrapper = mountWithAssignee({
      id: 9,
      name: 'Aria',
      type: 'agent_bot',
    });
    const aiChip = wrapper.find('.ai-chip');
    expect(aiChip.exists()).toBe(true);
    expect(aiChip.find('.i-lucide-sparkles').exists()).toBe(true);
    expect(aiChip.text()).toContain('Aria');
  });

  it('renders the AI chip even when showAssignee is false', () => {
    const wrapper = mountWithAssignee(
      { id: 9, name: 'Aria', type: 'agent_bot' },
      { showAssignee: false }
    );
    expect(wrapper.find('.ai-chip').exists()).toBe(true);
  });

  it('does not render the AI chip for a human assignee', () => {
    const wrapper = mountWithAssignee({ id: 9, name: 'Jane' });
    expect(wrapper.find('.ai-chip').exists()).toBe(false);
  });

  it('does not render the AI chip when there is no assignee', () => {
    const wrapper = mountWithAssignee(undefined);
    expect(wrapper.find('.ai-chip').exists()).toBe(false);
  });

  it('uses the sparkles icon instead of the bot icon', () => {
    const wrapper = mountWithAssignee({
      id: 9,
      name: 'Aria',
      type: 'agent_bot',
    });
    expect(wrapper.find('.ai-chip .i-lucide-sparkles').exists()).toBe(true);
    expect(wrapper.find('.i-lucide-bot').exists()).toBe(false);
  });

  it('uses the user icon for a human assignee', () => {
    const wrapper = mountWithAssignee(
      { id: 9, name: 'Jane' },
      { showAssignee: true }
    );
    expect(wrapper.find('.conversation--assignee').exists()).toBe(true);
    expect(wrapper.find('.i-lucide-user').exists()).toBe(true);
  });

  it('marks an unattended conversation assigned to the current user', () => {
    const wrapper = mountWithAssignee(
      { id: 1, name: 'Jane' },
      {},
      { waiting_since: 1234 }
    );
    expect(wrapper.vm.isUnattendedAndMine).toBe(true);
  });

  it('does not mistake an AI assignee id collision for the current user', () => {
    const wrapper = mountWithAssignee(
      { id: 1, name: 'Aria', type: 'agent_bot' },
      {},
      { waiting_since: 1234 }
    );
    expect(wrapper.vm.isUnattendedAndMine).toBe(false);
  });
});

describe('ConversationCard — SLA labels row', () => {
  it('does not reserve the row for only a persisted SLA policy id', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });
    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the row for an active applied SLA', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });
    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the row when the contact is blocked', () => {
    const wrapper = mountComponent(
      { sla_policy_id: 1, applied_sla: { id: 1 } },
      { blocked: true }
    );
    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });
});
