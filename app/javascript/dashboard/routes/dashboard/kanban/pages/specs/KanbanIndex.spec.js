import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanIndex from '../KanbanIndex.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: {
      accountId: '3',
      funnelId: '22',
    },
  }),
  useRouter: () => ({
    replace: vi.fn(),
    push: vi.fn(),
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const buildStore = (filters = {}) => {
  const viewFilters = {
    query: '',
    stageIds: [],
    labelIds: [],
    assigneeId: null,
    status: 'all',
    ...filters,
  };

  const store = createStore({
    getters: {
      getCurrentAccountId: () => 3,
      getCurrentUser: () => ({ id: 99 }),
    },
    modules: {
      kanban: {
        namespaced: true,
        getters: {
          getFunnels: () => [{ id: 22, name: 'Geral' }],
          getActiveFunnelId: () => 22,
          getViewMode: () => 'kanban',
          getViewFilters: () => viewFilters,
          getScheduledMessages: () => [],
          getFunnelStages: () => () => [{ id: 5, name: 'Abertos' }],
          getFunnelItems: () => () => [],
        },
      },
      labels: {
        namespaced: true,
        getters: {
          getLabels: () => [],
        },
      },
      agents: {
        namespaced: true,
        getters: {
          getAgents: () => [],
        },
      },
      conversations: {
        namespaced: true,
        getters: {
          getConversationById: () => () => null,
        },
      },
    },
  });

  vi.spyOn(store, 'dispatch').mockResolvedValue({});
  return store;
};

const mountComponent = filters =>
  shallowMount(KanbanIndex, {
    global: {
      plugins: [buildStore(filters)],
      stubs: {
        KanbanBoard: true,
        ListView: true,
        CalendarView: true,
        FunnelForm: true,
        ScheduledMessageForm: true,
        ScheduledMessagesDrawer: true,
        Dialog: true,
        Icon: true,
        KanbanFilterSelect: true,
        Button: {
          template:
            '<button type="button" @click="$emit(\'click\')"><slot /></button>',
        },
      },
    },
  });

describe('KanbanIndex.vue', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('keeps advanced filters panel closed by default', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-advanced-filters-panel"]').exists()
    ).toBe(false);
  });

  it('toggles advanced filters panel visibility', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    wrapper.vm.$.setupState.toggleAdvancedFilters();
    await wrapper.vm.$nextTick();
    expect(
      wrapper.find('[data-testid="kanban-advanced-filters-panel"]').exists()
    ).toBe(true);

    wrapper.vm.$.setupState.toggleAdvancedFilters();
    await wrapper.vm.$nextTick();
    expect(
      wrapper.find('[data-testid="kanban-advanced-filters-panel"]').exists()
    ).toBe(false);
  });

  it('shows active advanced filters count on the toggle button', async () => {
    const wrapper = mountComponent({
      stageIds: [5],
      labelIds: [1],
      status: 'open',
    });
    await flushPromises();

    expect(
      wrapper.get('[data-testid="kanban-advanced-filters-count"]').text()
    ).toBe('3');
  });
});
