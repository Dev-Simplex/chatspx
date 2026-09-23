import { shallowMount } from '@vue/test-utils';
import ListView from '../ListView.vue';
import { emitter } from 'shared/helpers/mitt';

const dispatch = vi.fn();
vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch,
    getters: {
      'kanban/getFunnelStages': () => [],
      'kanban/getViewFilters': {},
      'kanban/getViewBootstrap': {},
      'kanban/getUIFlags': {},
      'kanban/getScheduledMessages': [],
      'conversations/getConversationById': () => undefined,
      'conversationLabels/getConversationLabels': () => [],
      'kanban/getFunnelItems': () => [],
    },
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../composables/useStageColor', () => ({
  useStageColor: () => ({ accent: () => '#000', contrastText: () => '#fff' }),
}));

describe('ListView remove item', () => {
  it('alerts when deletion fails', async () => {
    dispatch.mockRejectedValueOnce(new Error('API failed'));
    const wrapper = shallowMount(ListView, { props: { funnelId: 22 } });
    const alert = vi.fn();
    emitter.on('newToastMessage', alert);
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);

    await wrapper.vm.$.setupState.handleRemove({ id: 7 });

    expect(dispatch).toHaveBeenCalledWith('kanban/deleteItem', {
      funnelId: 22,
      itemId: 7,
    });
    expect(alert).toHaveBeenCalledWith({
      message: 'KANBAN.ITEMS.REMOVE_ERROR',
      action: null,
    });
    emitter.off('newToastMessage', alert);
    confirm.mockRestore();
    wrapper.unmount();
  });
});
