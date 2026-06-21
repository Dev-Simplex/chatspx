import { createStore } from 'vuex';
import { flushPromises, mount } from '@vue/test-utils';
import ReplyBoxBanner from '../ReplyBoxBanner.vue';

const isAssignmentGateEnabled = { value: false };
vi.mock('dashboard/composables/useReplyAssignmentGate', () => ({
  useReplyAssignmentGate: () => ({ isAssignmentGateEnabled }),
}));

const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const BannerStub = {
  name: 'Banner',
  props: ['bannerMessage', 'actionButtonLabel', 'hasActionButton'],
  emits: ['primary-action'],
  template:
    '<div data-testid="banner" :data-label="actionButtonLabel">{{ bannerMessage }}<button data-testid="cta" @click="$emit(\'primary-action\')" /></div>',
};

const TeamSelectionModalStub = {
  name: 'TeamSelectionModal',
  template: '<div />',
};

const buildStore = chat => {
  const store = createStore({
    getters: {
      getSelectedChat: () => chat,
      getCurrentUser: () => ({ id: 1, name: 'Eu', avatar_url: '' }),
      'teams/getTeams': () => [],
    },
  });
  store.dispatch = vi.fn().mockResolvedValue({});
  return store;
};

const mountBanner = (chat, props = {}) => {
  const store = buildStore(chat);
  const wrapper = mount(ReplyBoxBanner, {
    props: { message: 'oi', isOnPrivateNote: false, ...props },
    global: {
      plugins: [store],
      stubs: {
        Banner: BannerStub,
        TeamSelectionModal: TeamSelectionModalStub,
      },
    },
  });
  return { wrapper, store };
};

// conversation owned by someone else => self-assign banner shows while typing
const CHAT_OTHER_OWNER = {
  id: 5,
  meta: { assignee: { id: 2, name: 'Colega' }, team: { id: 9 } },
};
const CHAT_UNASSIGNED = { id: 6, meta: {} };

describe('ReplyBoxBanner.vue (D3 gate)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isAssignmentGateEnabled.value = false;
  });

  it('classic mode: CTA self-assigns directly (no dialog event)', async () => {
    const { wrapper, store } = mountBanner(CHAT_OTHER_OWNER);
    await wrapper.find('[data-testid="cta"]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('openAssignDialog')).toBeUndefined();
    expect(store.dispatch).toHaveBeenCalledWith(
      'assignAgent',
      expect.objectContaining({ conversationId: 5, agentId: 1 })
    );
  });

  it('gate mode: CTA emits openAssignDialog and never dispatches assignAgent', async () => {
    isAssignmentGateEnabled.value = true;
    const { wrapper, store } = mountBanner(CHAT_OTHER_OWNER);
    await wrapper.find('[data-testid="cta"]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('openAssignDialog')).toHaveLength(1);
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'assignAgent',
      expect.anything()
    );
  });

  it('gate mode: uses the take-over CTA label', () => {
    isAssignmentGateEnabled.value = true;
    const { wrapper } = mountBanner(CHAT_UNASSIGNED);
    expect(
      wrapper.find('[data-testid="banner"]').attributes('data-label')
    ).toBe('Take over');
  });

  it('private note suppresses the banner entirely', () => {
    isAssignmentGateEnabled.value = true;
    const { wrapper } = mountBanner(CHAT_OTHER_OWNER, {
      isOnPrivateNote: true,
    });
    expect(wrapper.find('[data-testid="banner"]').exists()).toBe(false);
  });
});
