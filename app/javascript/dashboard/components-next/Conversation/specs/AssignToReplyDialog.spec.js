import { createStore } from 'vuex';
import { flushPromises, mount } from '@vue/test-utils';
import AssignToReplyDialog from '../AssignToReplyDialog.vue';

const fireTakeoverConfetti = vi.fn();
vi.mock('dashboard/components-next/effects/useConfetti', () => ({
  fireTakeoverConfetti: (...args) => fireTakeoverConfetti(...args),
}));

// `Motion` (motion-v) is a renderless wrapper in the dialog body — stub it to a
// plain div so the slot content renders in JSDOM without the animation engine.
const MotionStub = {
  name: 'Motion',
  template: '<div><slot /></div>',
};

// `Dialog` exposes the imperative open()/close() API. Stub keeps the slot and
// re-emits confirm so we can drive onConfirm from the test.
const DialogStub = {
  name: 'Dialog',
  props: [
    'title',
    'description',
    'confirmButtonLabel',
    'cancelButtonLabel',
    'isLoading',
    'disableConfirmButton',
    'type',
    'width',
  ],
  emits: ['confirm'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template:
    '<div data-testid="dialog"><h3>{{ title }}</h3><p>{{ description }}</p><slot /></div>',
};

const AvatarStub = {
  name: 'Avatar',
  props: ['name', 'size'],
  template: '<div data-testid="avatar">{{ name }}</div>',
};

const buildStore = ({ chat, currentUser, myTeams = [], allTeams = [] }) => {
  const store = createStore({
    getters: {
      getSelectedChat: () => chat,
      getCurrentUser: () => currentUser,
      'teams/getMyTeams': () => myTeams,
      'teams/getTeams': () => allTeams,
    },
  });
  store.dispatch = vi.fn().mockResolvedValue({});
  return store;
};

const mountDialog = state =>
  mount(AssignToReplyDialog, {
    global: {
      plugins: [buildStore(state)],
      // mount (not shallowMount) so the Dialog/Motion default slots pass the
      // team list/avatar through; Dialog is stubbed to skip native showModal.
      stubs: { Dialog: DialogStub, Avatar: AvatarStub, Motion: MotionStub },
    },
  });

const CURRENT_USER = { id: 1, name: 'Eu' };

describe('AssignToReplyDialog.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // The component resolves TITLE/DESC/CONFIRM via useI18n().t() (real i18n in
  // the test runner) — so we read the Dialog stub's `title` prop, which carries
  // the resolved English copy for each variant.
  const titleOf = wrapper => wrapper.findComponent(DialogStub).props('title');

  it('resolves variant (a) for a conversation with no owner', async () => {
    const wrapper = mountDialog({
      chat: { id: 10, meta: {} },
      currentUser: CURRENT_USER,
    });
    wrapper.vm.show();
    await flushPromises();
    expect(wrapper.find('[data-testid="dialog"]').exists()).toBe(true);
    expect(titleOf(wrapper)).toBe('No one owns this conversation');
  });

  it('resolves variant (b) for a colleague-owned conversation', async () => {
    const wrapper = mountDialog({
      chat: { id: 11, meta: { assignee: { id: 2, name: 'Colega' } } },
      currentUser: CURRENT_USER,
    });
    wrapper.vm.show();
    await flushPromises();
    expect(titleOf(wrapper)).toBe("Colega's conversation");
  });

  it('resolves variant (c) when the owner is an agent_bot (AI)', async () => {
    const wrapper = mountDialog({
      chat: {
        id: 12,
        meta: { assignee: { id: 5, name: 'Júlia', type: 'agent_bot' } },
      },
      currentUser: CURRENT_USER,
    });
    wrapper.vm.show();
    await flushPromises();
    expect(titleOf(wrapper)).toBe('Handled by AI Júlia');
    // confirm label uses the (c) variant copy
    expect(wrapper.findComponent(DialogStub).props('confirmButtonLabel')).toBe(
      'Take over from Júlia and send'
    );
  });

  it('resolves variant (d) when the user is not a member of the conversation team', async () => {
    const wrapper = mountDialog({
      chat: { id: 13, meta: { team: { id: 9, name: 'Vendas' } } },
      currentUser: CURRENT_USER,
      myTeams: [{ id: 7, name: 'Suporte' }],
      allTeams: [
        { id: 7, name: 'Suporte', is_member: true },
        { id: 9, name: 'Vendas', is_member: false },
      ],
    });
    wrapper.vm.show();
    await flushPromises();
    expect(titleOf(wrapper)).toBe("You're not part of this team");
    // renders a team radio per team in getMyTeams (only the user's own teams).
    const radios = wrapper.findAll('input[type="radio"]');
    expect(radios).toHaveLength(1);
    const labels = wrapper.findAll('label').map(l => l.text());
    expect(labels).toEqual(['Suporte']); // never team 9 (Vendas)
  });

  it('fails open to membership when the teams store is empty', async () => {
    const wrapper = mountDialog({
      chat: { id: 14, meta: { team: { id: 9, name: 'Vendas' } } },
      currentUser: CURRENT_USER,
      myTeams: [],
      allTeams: [],
    });
    wrapper.vm.show();
    await flushPromises();
    // no team known => treated as member => variant (a), not (d)
    expect(titleOf(wrapper)).toBe('No one owns this conversation');
  });

  it('show(meta) from the 422 overrides the store assignee (race P16)', async () => {
    const wrapper = mountDialog({
      chat: { id: 15, meta: {} }, // store says "no owner"
      currentUser: CURRENT_USER,
    });
    wrapper.vm.show({
      current_assignee: { id: 2, name: 'Outro', type: 'User' },
      team: null,
    });
    await flushPromises();
    // meta wins => colleague variant (b), not the store's (a)
    expect(titleOf(wrapper)).toBe("Outro's conversation");
  });

  it('confirm dispatches assignTeam then assignAgent (variant d) and emits confirm', async () => {
    const wrapper = mountDialog({
      chat: { id: 16, meta: { team: { id: 9, name: 'Vendas' } } },
      currentUser: CURRENT_USER,
      myTeams: [{ id: 7, name: 'Suporte' }],
      allTeams: [
        { id: 7, name: 'Suporte', is_member: true },
        { id: 9, name: 'Vendas', is_member: false },
      ],
    });
    const store = wrapper.vm.$.appContext.config.globalProperties.$store;
    wrapper.vm.show();
    await flushPromises();
    // single team => pre-selected
    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    const calls = store.dispatch.mock.calls.map(c => c[0]);
    expect(calls).toEqual(['assignTeam', 'assignAgent']);
    expect(store.dispatch).toHaveBeenNthCalledWith(1, 'assignTeam', {
      conversationId: 16,
      teamId: 7,
      rethrow: true,
    });
    expect(store.dispatch).toHaveBeenNthCalledWith(2, 'assignAgent', {
      conversationId: 16,
      agentId: 1,
      rethrow: true,
    });
    expect(fireTakeoverConfetti).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('confirm')).toHaveLength(1);
  });

  it('variant (a) with 0 user teams self-assigns without requiring a team', async () => {
    const wrapper = mountDialog({
      chat: { id: 17, meta: {} },
      currentUser: CURRENT_USER,
      myTeams: [],
      allTeams: [],
    });
    const store = wrapper.vm.$.appContext.config.globalProperties.$store;
    wrapper.vm.show();
    await flushPromises();
    await wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    const calls = store.dispatch.mock.calls.map(c => c[0]);
    expect(calls).toEqual(['assignAgent']); // no assignTeam
    expect(wrapper.emitted('confirm')).toHaveLength(1);
  });
});
