import { createStore } from 'vuex';
import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import SidepanelSwitch from '../SidepanelSwitch.vue';

const updateUISettings = vi.fn();
const uiSettings = ref({
  is_contact_sidebar_open: true,
  is_copilot_panel_open: false,
});

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings,
    updateUISettings,
  }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
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
    uiSettings.value = {
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    };
  });

  it('renders schedule quick action when a conversation is active', () => {
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
    ).toBe(true);
  });

  it('opens scheduled message form with mapped current conversation payload', async () => {
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

    await wrapper
      .find('[data-testid="conversation-sidebar-schedule-toggle"]')
      .trigger('click');

    const scheduledForm = wrapper.findComponent(ScheduledMessageFormStub);

    expect(scheduledForm.props('show')).toBe(true);
    expect(scheduledForm.props('requireConversation')).toBeTruthy();
    expect(scheduledForm.props('conversation')).toMatchObject({
      id: 654,
      inboxId: 22,
      inbox_id: 22,
      contact: {
        id: 88,
        name: 'Maria',
      },
    });

    scheduledForm.vm.$emit('close');
    await nextTick();

    expect(wrapper.findComponent(ScheduledMessageFormStub).props('show')).toBe(
      false
    );
  });
});
