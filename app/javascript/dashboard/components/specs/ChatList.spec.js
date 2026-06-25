import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import ChatList from '../ChatList.vue';
import ChatTypeTabs from '../widgets/ChatTypeTabs.vue';

// Partial factory (instead of automock): dashboard/routes/index.js builds a
// real router at import time (createRouter().onError(...)) and enters the
// module graph transitively through ChatList children.
vi.mock('vue-router', () => ({
  useRoute: vi.fn(),
  useRouter: vi.fn(),
  createRouter: vi.fn(() => ({
    onError: vi.fn(),
    beforeEach: vi.fn(),
    afterEach: vi.fn(),
    push: vi.fn(),
    resolve: vi.fn(),
  })),
  createWebHistory: vi.fn(() => ({})),
  RouterLink: { template: '<a><slot /></a>' },
  RouterView: { template: '<div><slot /></div>' },
}));
// lottie-web creates a canvas at import time, which jsdom does not implement —
// it enters the module graph transitively through the dashboard routes.
vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const CURRENT_USER = {
  id: 1,
  name: 'Agent',
  accounts: [{ id: 1, role: 'administrator', permissions: ['administrator'] }],
};

const buildStore = ({
  gateEnabled = false,
  assistants = [],
  stats = {},
} = {}) => {
  const statsState = {
    mineCount: 0,
    unAssignedCount: 0,
    aiCount: 0,
    allCount: 0,
    unattendedAssignedCount: 0,
    unattendedUnassignedCount: 0,
    unattendedAllCount: 0,
    updatedOn: null,
    ...stats,
  };
  const noop = () => {};
  const captainGet = vi.fn();

  const store = createStore({
    state: {},
    getters: {
      getCurrentUser: () => CURRENT_USER,
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'administrator',
      getFilteredConversations: () => [],
      getMineChats: () => [],
      getAllStatusChats: () => [],
      getUnAssignedChats: () => [],
      getAIChats: () => [],
      getAwaitingChats: () => [],
      getChatListLoadingStatus: () => false,
      getSelectedInbox: () => 0,
      getAppliedConversationFiltersV2: () => [],
      getConversationById: () => () => undefined,
      getUISettings: () => ({}),
    },
    actions: {
      setChatListFilters: noop,
      updateChatListFilters: noop,
      setChatStatusFilter: noop,
      setChatSortFilter: noop,
      emptyAllConversations: noop,
      clearConversationFilters: noop,
      fetchAllConversations: noop,
    },
    modules: {
      conversationStats: {
        namespaced: true,
        state: statsState,
        getters: { getStats: $state => $state },
        mutations: {
          setStats($state, payload) {
            Object.assign($state, payload);
          },
        },
        actions: { get: noop },
      },
      captainAssistants: {
        namespaced: true,
        state: { records: assistants },
        getters: { getRecords: $state => $state.records },
        actions: { get: captainGet },
      },
      accounts: {
        namespaced: true,
        getters: {
          getAccount: () => () => ({
            id: 1,
            settings: { reply_assignment_gate: gateEnabled },
          }),
          isFeatureEnabledonAccount: () => () => false,
        },
      },
      globalConfig: {
        namespaced: true,
        getters: { isOnChatwootCloud: () => false },
      },
      conversationPage: {
        namespaced: true,
        getters: {
          getCurrentPageFilter: () => () => 0,
          getHasEndReached: () => () => false,
          getNextCursor: () => () => null,
        },
        actions: { reset: noop },
      },
      bulkActions: {
        namespaced: true,
        getters: { getSelectedConversationIds: () => [] },
        actions: { clearSelectedConversationIds: noop },
      },
      customViews: {
        namespaced: true,
        getters: { getConversationCustomViews: () => [] },
        actions: { setActiveConversationFolder: noop },
      },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [] },
      },
      teams: {
        namespaced: true,
        getters: {
          getTeams: () => [],
          getMyTeams: () => [],
          getTeam: () => () => ({}),
        },
      },
      inboxes: {
        namespaced: true,
        getters: {
          getInboxes: () => [],
          getInbox: () => () => ({}),
        },
      },
      campaigns: {
        namespaced: true,
        getters: { getAllCampaigns: () => [] },
        actions: { get: noop },
      },
      labels: {
        namespaced: true,
        getters: { getLabels: () => [] },
      },
      attributes: {
        namespaced: true,
        getters: {
          getAttributesByModel: () => () => [],
          getConversationAttributes: () => [],
        },
      },
      conversationSearch: {
        namespaced: true,
        getters: {
          getConversationRecords: () => [],
          getConversationSearchQuery: () => '',
          getConversationSearchCompleted: () => false,
          getUIFlags: () => ({ conversation: { isFetching: false } }),
        },
        actions: { clearSearchResults: noop },
      },
    },
  });

  return { store, captainGet };
};

const mountChatList = (storeOptions = {}, props = {}) => {
  const { store, captainGet } = buildStore(storeOptions);
  const wrapper = shallowMount(ChatList, {
    props,
    global: { plugins: [store] },
  });
  return { wrapper, store, captainGet };
};

const tabKeys = wrapper =>
  wrapper
    .findComponent(ChatTypeTabs)
    .props('items')
    .map(item => item.key);

describe('ChatList — assignee tabs (Fase C)', () => {
  beforeEach(() => {
    useRoute.mockReturnValue({
      name: 'home',
      query: {},
      params: { accountId: '1' },
    });
    useRouter.mockReturnValue({ push: vi.fn() });
  });

  describe('with the assignment gate OFF', () => {
    it('keeps the three classic tabs without variant', () => {
      const { wrapper } = mountChatList({
        gateEnabled: false,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: { mineCount: 1, unAssignedCount: 0, aiCount: 2, allCount: 3 },
      });
      const items = wrapper.findComponent(ChatTypeTabs).props('items');
      expect(items.map(item => item.key)).toEqual(['me', 'unassigned', 'all']);
      expect(items.every(item => item.variant === undefined)).toBe(true);
    });

    it('does not fetch captain assistants', () => {
      const { captainGet } = mountChatList({ gateEnabled: false });
      expect(captainGet).not.toHaveBeenCalled();
    });
  });

  describe('with the assignment gate ON', () => {
    it('shows Mine/Awaiting/AI/All as dynamic tabs (counts > 0), never the unassigned chip', () => {
      // Abas dinâmicas: "Aguardando atendimento" (awaiting_count > 0) e "IA"
      // (ai_count > 0) só aparecem quando têm conteúdo. A ordem é
      // Minhas / Aguardando atendimento / IA / Todas. "Não atribuídas" deixa de
      // ser chip no modo IA.
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: {
          mineCount: 1,
          unAssignedCount: 2,
          awaitingCount: 3,
          aiCount: 4,
          allCount: 7,
        },
      });
      const items = wrapper.findComponent(ChatTypeTabs).props('items');
      expect(items.map(item => item.key)).toEqual([
        'me',
        'awaiting',
        'ai',
        'all',
      ]);
      expect(items.find(item => item.key === 'unassigned')).toBeUndefined();

      const awaitingTab = items.find(item => item.key === 'awaiting');
      expect(awaitingTab.icon).toBe('i-lucide-clock');
      expect(awaitingTab.count).toBe(3);

      const aiTab = items.find(item => item.key === 'ai');
      expect(aiTab.variant).toBeUndefined();
      expect(aiTab.icon).toBe('i-lucide-sparkles');
      expect(aiTab.count).toBe(4);
    });

    it('hides the Awaiting tab when awaiting_count is zero', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: { awaitingCount: 0, aiCount: 1, allCount: 1 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'ai', 'all']);
    });

    it('hides the AI tab when ai_count is zero (regardless of assistants)', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: {
          awaitingCount: 0,
          aiCount: 0,
          unAssignedCount: 2,
          allCount: 5,
        },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'all']);
    });

    it('shows the AI tab on count even when the account has no assistants', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [],
        stats: { aiCount: 2, allCount: 4 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'ai', 'all']);
    });

    it('fetches captain assistants on mount', () => {
      const { captainGet } = mountChatList({ gateEnabled: true });
      expect(captainGet).toHaveBeenCalled();
    });

    it('keeps the three classic tabs on the unattended view', () => {
      useRoute.mockReturnValue({
        name: 'conversation_unattended',
        query: {},
        params: { accountId: '1' },
      });
      const { wrapper } = mountChatList(
        {
          gateEnabled: true,
          assistants: [{ id: 1, name: 'Aria' }],
          stats: {
            unAssignedCount: 0,
            awaitingCount: 5,
            aiCount: 5,
            unattendedAssignedCount: 1,
            unattendedUnassignedCount: 2,
            allCount: 3,
          },
        },
        { conversationType: 'unattended' }
      );
      const items = wrapper.findComponent(ChatTypeTabs).props('items');
      // Awaiting/AI nunca aparecem na visão de não-respondidas (sem contadores
      // per-awaiting/per-AI lá).
      expect(items.map(item => item.key)).toEqual(['me', 'unassigned', 'all']);
      expect(items.find(item => item.key === 'me').count).toBe(1);
      expect(items.find(item => item.key === 'unassigned').count).toBe(2);
    });
  });
});
