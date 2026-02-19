import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanColumn from '../KanbanColumn.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const DraggableStub = {
  name: 'draggable',
  template: '<div><slot /></div>',
};

const buildStore = () => {
  const store = createStore({
    modules: {
      kanban: {
        namespaced: true,
        getters: {
          getStageMeta: () => () => ({
            hasMore: false,
            nextCursor: null,
            isLoading: false,
            loaded: true,
            error: false,
            limit: 30,
          }),
        },
      },
    },
  });

  vi.spyOn(store, 'dispatch').mockResolvedValue({});
  return store;
};

const mountComponent = () =>
  shallowMount(KanbanColumn, {
    props: {
      funnelId: 22,
      stage: {
        id: 44,
        name: 'Resolvidos',
        automationType: 'resolved',
      },
      items: [],
      conversations: {},
    },
    global: {
      plugins: [buildStore()],
      stubs: {
        draggable: DraggableStub,
        KanbanCard: true,
        Icon: true,
        Button: true,
        IntersectionObserver: true,
      },
    },
  });

describe('KanbanColumn.vue', () => {
  it('emits moveItem payload from drop change event', async () => {
    const wrapper = mountComponent();
    const draggable = wrapper.findComponent(DraggableStub);

    draggable.vm.$emit('change', {
      added: {
        element: {
          id: 2528,
          funnel_stage_id: 5,
        },
        newIndex: 0,
        oldIndex: null,
      },
    });

    expect(wrapper.emitted('moveItem')).toBeTruthy();
    expect(wrapper.emitted('moveItem')[0][0]).toEqual({
      item: {
        id: 2528,
        funnel_stage_id: 5,
      },
      newIndex: 0,
      oldIndex: null,
      stageId: 44,
    });
  });

  it('does not emit moveItem when event has no added item', async () => {
    const wrapper = mountComponent();
    const draggable = wrapper.findComponent(DraggableStub);

    draggable.vm.$emit('change', {
      removed: {
        element: { id: 2528 },
      },
    });

    expect(wrapper.emitted('moveItem')).toBeFalsy();
  });
});
