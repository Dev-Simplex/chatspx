import { h, nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import ContactPanel from '../ContactPanel.vue';

const state = vi.hoisted(() => ({
  dispatch: vi.fn(),
  selectedChat: {
    custom_attributes: { captador_lead_id: 'lead-conversa-1' },
    meta: { channel: 'Channel::Whatsapp', sender: { id: 7 } },
  },
  contact: { custom_attributes: {}, additional_attributes: {} },
}));

vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: state.dispatch }),
  useMapGetter: key => ({
    value: {
      getSelectedChat: state.selectedChat,
      'macros/getMacros': [],
      'conversationMetadata/getConversationMetadata': () => ({
        additional_attributes: {},
      }),
      'contacts/getContact': () => state.contact,
    }[key],
  }),
  useFunctionGetter: (_key, integration) => ({
    value: integration === 'captador' ? { enabled: true } : { enabled: false },
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
vi.mock('dashboard/composables/useGroupConversation', () => ({
  useGroupConversation: () => ({
    isGroup: { value: false },
    participantCount: { value: 0 },
    hasSnapshot: { value: false },
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: () => false,
    conversationSidebarItemsOrder: {
      value: [{ name: 'captador_lead' }],
    },
    toggleSidebarUIState: vi.fn(),
  }),
}));

const DraggableStub = {
  props: { list: { type: Array, default: () => [] } },
  setup(props, { slots }) {
    return () => h('div', props.list.map(element => slots.item?.({ element })));
  },
};
const CaptadorLeadStub = {
  name: 'CaptadorLead',
  props: ['conversationId', 'leadId'],
  template: '<div />',
};

describe('ContactPanel', () => {
  it('repassa o captador_lead_id da conversa ao painel do Captador', async () => {
    const wrapper = shallowMount(ContactPanel, {
      props: { conversationId: 99 },
      global: {
        mocks: { $t: key => key },
        stubs: {
          Draggable: DraggableStub,
          AccordionItem: { template: '<div><slot /></div>' },
          CaptadorLead: CaptadorLeadStub,
        },
      },
    });

    await nextTick();

    expect(wrapper.findComponent(CaptadorLeadStub).props()).toMatchObject({
      conversationId: 99,
      leadId: 'lead-conversa-1',
    });
  });
});
