import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import AIAgentsSection from '../AIAgentsSection.vue';

const getSpy = vi.fn();

const AvatarStub = {
  name: 'Avatar',
  props: {
    src: { type: String, default: '' },
    name: { type: String, default: '' },
    size: { type: Number, default: 32 },
  },
  template: '<span data-testid="avatar" />',
};

const buildStore = ({ assistants = [], inboxes = [] } = {}) =>
  createStore({
    modules: {
      captainAssistants: {
        namespaced: true,
        getters: {
          getRecords: () => assistants,
          getUIFlags: () => ({ fetchingList: false }),
        },
        actions: { get: getSpy },
      },
      inboxes: {
        namespaced: true,
        getters: {
          getInboxes: () => inboxes,
        },
      },
    },
  });

const mountComponent = (state = {}) =>
  mount(AIAgentsSection, {
    global: {
      plugins: [buildStore(state)],
      stubs: { Avatar: AvatarStub },
    },
  });

const inboxes = [
  { id: 1, name: 'Suporte' },
  { id: 2, name: 'Vendas' },
];

const assistants = [
  {
    id: 7,
    name: 'Sales Assistant',
    description: 'Handles sales conversations',
    avatar_url: 'http://example.com/avatar-7.png',
    agent_bot_id: 70,
    inbox_ids: [1, 2],
  },
  {
    id: 8,
    name: 'Support Assistant',
    description: '',
    avatar_url: '',
    agent_bot_id: 80,
    inbox_ids: [],
  },
];

describe('AIAgentsSection', () => {
  beforeEach(() => {
    getSpy.mockClear();
  });

  it('hides the whole section when there are no assistants', () => {
    const wrapper = mountComponent({ assistants: [], inboxes });
    expect(wrapper.find('section').exists()).toBe(false);
  });

  it('dispatches captainAssistants/get on mount', () => {
    mountComponent({ assistants, inboxes });
    expect(getSpy).toHaveBeenCalledTimes(1);
  });

  it('renders one row per assistant with name, avatar and section heading', () => {
    const wrapper = mountComponent({ assistants, inboxes });
    expect(wrapper.find('section').exists()).toBe(true);
    expect(wrapper.find('h2').text()).toBe('AI Agents');
    expect(wrapper.findAll('[data-testid="avatar"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('Sales Assistant');
    expect(wrapper.text()).toContain('Support Assistant');
    expect(wrapper.text()).toContain('Handles sales conversations');
  });

  it('renders the AI Agent badge for every assistant', () => {
    const wrapper = mountComponent({ assistants, inboxes });
    const badges = wrapper
      .findAll('span')
      .filter(span => span.text() === 'AI Agent');
    expect(badges).toHaveLength(2);
  });

  it('maps inbox ids to inbox name chips and skips unknown ids', () => {
    const withUnknownInbox = [{ ...assistants[0], inbox_ids: [1, 99] }];
    const wrapper = mountComponent({ assistants: withUnknownInbox, inboxes });
    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).not.toContain('Vendas');
    expect(wrapper.text()).not.toContain('99');
  });

  it('shows the empty inboxes message when the assistant has no eligible inbox', () => {
    const wrapper = mountComponent({ assistants: [assistants[1]], inboxes });
    expect(wrapper.text()).toContain('No eligible inboxes');
  });

  it('is read-only: renders no action buttons', () => {
    const wrapper = mountComponent({ assistants, inboxes });
    expect(wrapper.findAll('button')).toHaveLength(0);
  });
});
