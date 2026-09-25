import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import ChatList from '../ChatList.vue';
import ChatTypeTabs from '../widgets/ChatTypeTabs.vue';
import { emitter } from 'shared/helpers/mitt';

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
  user = CURRENT_USER,
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
      getCurrentUser: () => user,
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'administrator',
      getFilteredConversations: () => [],
      getMineChats: () => [],
      getAllStatusChats: () => [],
      getUnAssignedChats: () => [],
      getAIChats: () => [],
      getRodizioChats: () => [],
      getPendingClosureChats: () => [],
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
          getVisibleTeams: () => [],
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

describe('ChatList — mark as read or unread errors', () => {
  beforeEach(() => {
    useRoute.mockReturnValue({
      name: 'home',
      query: {},
      params: { accountId: '1' },
    });
    useRouter.mockReturnValue({ push: vi.fn() });
  });

  it.each([
    [
      'markAsUnread',
      'markMessagesUnread',
      'Could not mark the conversation as unread. Try again.',
    ],
    [
      'markAsRead',
      'markMessagesRead',
      'Could not mark the conversation as read. Try again.',
    ],
  ])(
    '%s shows an alert when the action fails',
    async (method, action, message) => {
      const { wrapper, store } = mountChatList();
      const alert = vi.fn();
      emitter.on('newToastMessage', alert);
      vi.spyOn(store, 'dispatch').mockImplementation(type =>
        type === action
          ? Promise.reject(new Error('API failed'))
          : Promise.resolve()
      );

      await wrapper.vm.$.provides[method](42);

      expect(alert).toHaveBeenCalledWith({ message, action: null });
      emitter.off('newToastMessage', alert);
      wrapper.unmount();
    }
  );
});

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
    it('admin sees Mine/Rotation/Attention/AI/All, never the unassigned chip', () => {
      // Admin/supervisor: "Rodízio" sempre; "Atenção" e "IA" quando têm conteúdo.
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: {
          mineCount: 1,
          unAssignedCount: 2,
          rodizioCount: 0,
          awaitingClosureCount: 3,
          aiCount: 4,
          allCount: 7,
        },
      });
      const items = wrapper.findComponent(ChatTypeTabs).props('items');
      expect(items.map(item => item.key)).toEqual([
        'me',
        'rodizio',
        'pending_closure',
        'ai',
        'all',
      ]);
      expect(items.find(item => item.key === 'rodizio').variant).toBe('alert');
      expect(items.find(item => item.key === 'pending_closure').count).toBe(3);
      expect(items.find(item => item.key === 'ai').count).toBe(4);
    });

    it('hides Attention when awaiting_closure_count is zero', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        stats: { awaitingClosureCount: 0, aiCount: 1, allCount: 1 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'rodizio', 'ai', 'all']);
    });

    it('agent sees Rotation only on their turn, and never Attention', () => {
      const agent = {
        id: 2,
        name: 'Agent',
        accounts: [{ id: 1, role: 'agent', permissions: ['agent'] }],
      };
      const stats = { awaitingClosureCount: 3, aiCount: 1, allCount: 4 };
      const { wrapper } = mountChatList({
        gateEnabled: true,
        user: agent,
        stats: { ...stats, rodizioCount: 0 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'ai', 'all']);

      const { wrapper: onTurn } = mountChatList({
        gateEnabled: true,
        user: agent,
        stats: { ...stats, rodizioCount: 1 },
      });
      expect(tabKeys(onTurn)).toEqual(['me', 'rodizio', 'ai', 'all']);
    });

    it('supervisor sees Rotation and Attention like the admin', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        user: {
          id: 3,
          name: 'Sup',
          accounts: [
            { id: 1, role: 'agent', permissions: ['agent', 'team_supervisor'] },
          ],
        },
        stats: { awaitingClosureCount: 2, allCount: 2 },
      });
      expect(tabKeys(wrapper)).toEqual([
        'me',
        'rodizio',
        'pending_closure',
        'all',
      ]);
    });

    it('hides the AI tab when ai_count is zero (regardless of assistants)', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [{ id: 1, name: 'Aria' }],
        stats: { aiCount: 0, unAssignedCount: 2, allCount: 5 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'rodizio', 'all']);
    });

    it('shows the AI tab on count even when the account has no assistants', () => {
      const { wrapper } = mountChatList({
        gateEnabled: true,
        assistants: [],
        stats: { aiCount: 2, allCount: 4 },
      });
      expect(tabKeys(wrapper)).toEqual(['me', 'rodizio', 'ai', 'all']);
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
            rodizioCount: 5,
            aiCount: 5,
            unattendedAssignedCount: 1,
            unattendedUnassignedCount: 2,
            allCount: 3,
          },
        },
        { conversationType: 'unattended' }
      );
      const items = wrapper.findComponent(ChatTypeTabs).props('items');
      // Rodízio/Atenção/IA nunca aparecem na visão de não-respondidas (sem
      // contadores per-fila lá).
      expect(items.map(item => item.key)).toEqual(['me', 'unassigned', 'all']);
      expect(items.find(item => item.key === 'me').count).toBe(1);
      expect(items.find(item => item.key === 'unassigned').count).toBe(2);
    });
  });
});
