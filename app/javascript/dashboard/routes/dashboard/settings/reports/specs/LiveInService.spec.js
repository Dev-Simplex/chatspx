import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import LiveInService from '../LiveInService.vue';
import LiveReportsAPI from 'dashboard/api/liveReports';

const mockStore = {
  dispatch: vi.fn(),
  getters: {},
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');

  return {
    useStore: () => mockStore,
    useMapGetter: key => computed(() => mockStore.getters[key]),
  };
});

vi.mock('dashboard/composables/useLiveRefresh', () => ({
  useLiveRefresh: () => ({
    startRefetching: vi.fn(),
    stopRefetching: vi.fn(),
  }),
}));

vi.mock('dashboard/api/teams', () => ({
  default: {
    getAgents: vi.fn(),
  },
}));

vi.mock('dashboard/api/liveReports', () => ({
  default: {
    getInServiceOverview: vi.fn(),
    getInServiceConversations: vi.fn(),
  },
}));

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe('LiveInService.vue', () => {
  const mountComponent = () =>
    shallowMount(LiveInService, {
      global: {
        mocks: {
          $t: key => key,
        },
        stubs: {
          ReportHeader: true,
          LiveFilters: true,
          AgentCard: true,
          AgentCardSkeleton: true,
          ConversationItem: true,
          EmptyState: true,
          Button: true,
          CreepyButton: true,
          IntersectionObserver: true,
        },
      },
    });

  beforeEach(() => {
    mockStore.dispatch = vi.fn().mockResolvedValue({});
    mockStore.getters = {
      'agents/getAgents': [
        {
          id: 1,
          name: 'Agent One',
          available_name: 'Agent One',
          thumbnail: '',
          availability_status: 'online',
          team_ids: [],
        },
      ],
    };

    LiveReportsAPI.getInServiceOverview.mockResolvedValue({
      data: {
        totals: {
          in_service: 1,
          waiting: 0,
          agents_with_conversations: 1,
        },
        agents: [
          {
            assignee_id: 1,
            in_service: 1,
            open: 1,
            pending: 0,
          },
        ],
      },
    });

    LiveReportsAPI.getInServiceConversations.mockResolvedValue({
      data: {
        payload: [],
        meta: {
          next_cursor: null,
          has_more: false,
        },
      },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('loads overview and first agent preview on mount', async () => {
    mountComponent();

    await flushPromises();
    await nextTick();
    await flushPromises();

    expect(mockStore.dispatch).toHaveBeenCalledWith('agents/get');
    expect(mockStore.dispatch).toHaveBeenCalledWith('teams/get');
    expect(LiveReportsAPI.getInServiceOverview).toHaveBeenCalledTimes(1);
    expect(LiveReportsAPI.getInServiceConversations).toHaveBeenCalledWith({
      scope: 'agent',
      assignee_id: 1,
      limit: 5,
    });
  });
});
