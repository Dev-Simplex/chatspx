import { createStore } from 'vuex';
import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import SidepanelSwitch from '../SidepanelSwitch.vue';

const updateUISettings = vi.fn();
const uiSettings = ref({
  is_contact_sidebar_open: true,
  is_copilot_panel_open: false,
});

const emitterListeners = new Map();

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings,
    updateUISettings,
  }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

vi.mock('dashboard/composables/emitter', () => ({
  useEmitter: (eventName, callback) => {
    emitterListeners.set(eventName, callback);
  },
}));

const ButtonGroupStub = {
  name: 'ButtonGroup',
  template: '<div><slot /></div>',
};

const ButtonStub = {
  name: 'Button',
  inheritAttrs: false,
  props: {
    icon: {
      type: String,
      default: '',
    },
  },
  emits: ['click'],
  template:
    '<button v-bind="$attrs" :data-icon="icon" @click="$emit(\'click\')"><slot /></button>',
};

const ScheduledMessageFormStub = {
  name: 'ScheduledMessageForm',
  props: {
    show: Boolean,
    conversation: {
      type: Object,
      default: () => ({}),
    },
    requireConversation: Boolean,
  },
  template: '<div data-testid="scheduled-message-form-stub" />',
};

const buildStore = currentChat =>
  createStore({
    getters: {
      getCurrentAccountId: () => 3,
      getSelectedChat: () => currentChat,
      'accounts/isFeatureEnabledonAccount': () => () => false,
    },
  });

const mountComponent = currentChat =>
  shallowMount(SidepanelSwitch, {
    global: {
      plugins: [buildStore(currentChat)],
      stubs: {
        ButtonGroup: ButtonGroupStub,
        Button: ButtonStub,
        ScheduledMessageForm: ScheduledMessageFormStub,
      },
    },
  });

describe('SidepanelSwitch.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    emitterListeners.clear();
    uiSettings.value = {
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    };
  });

  it('does not render the schedule button (moved to reply box)', () => {
    const wrapper = mountComponent({
      id: 321,
      inbox_id: 17,
      meta: {
        sender: {
          id: 55,
          name: 'Contato Teste',
        },
      },
    });

    expect(
      wrapper
        .find('[data-testid="conversation-sidebar-schedule-toggle"]')
        .exists()
    ).toBe(false);
  });

  it('opens scheduled message form via open-schedule-message-form emitter event', async () => {
    const wrapper = mountComponent({
      id: 654,
      inbox_id: 22,
      meta: {
        sender: {
          id: 88,
          name: 'Maria',
        },
      },
    });

    const scheduledForm = wrapper.findComponent(ScheduledMessageFormStub);
    expect(scheduledForm.props('show')).toBe(false);

    const handler = emitterListeners.get('open-schedule-message-form');
    expect(handler).toBeTypeOf('function');
    handler();
    await nextTick();

    const opened = wrapper.findComponent(ScheduledMessageFormStub);
    expect(opened.props('show')).toBe(true);
    expect(opened.props('requireConversation')).toBeTruthy();
    expect(opened.props('conversation')).toMatchObject({
      id: 654,
      inboxId: 22,
      inbox_id: 22,
      contact: {
        id: 88,
        name: 'Maria',
      },
    });

    opened.vm.$emit('close');
    await nextTick();

    expect(wrapper.findComponent(ScheduledMessageFormStub).props('show')).toBe(
      false
    );
  });

  it('does not open the form when there is no active conversation', async () => {
    const wrapper = mountComponent(undefined);

    const handler = emitterListeners.get('open-schedule-message-form');
    expect(handler).toBeTypeOf('function');
    handler();
    await nextTick();

    expect(wrapper.findComponent(ScheduledMessageFormStub).props('show')).toBe(
      false
    );
  });
});
