import { shallowMount } from '@vue/test-utils';

const isAssignmentGateEnabled = { value: false };
const translate = vi.fn(key =>
  key === 'BULK_ACTION.NONE' ? 'Translated None' : key
);

vi.mock('dashboard/composables/useReplyAssignmentGate', () => ({
  useReplyAssignmentGate: () => ({ isAssignmentGateEnabled }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    const values = {
      'inboxAssignableAgents/getUIFlags': { isFetching: false },
      'bulkActions/getUIFlags': { isUpdating: false },
      'inboxAssignableAgents/getAssignableAgents': () => [
        { id: 1, name: 'Ada', thumbnail: '' },
      ],
    };
    return { value: values[key] };
  },
}));

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: translate }),
  I18nT: { template: '<p><slot /></p>' },
}));

import BulkAgentActions from '../BulkAgentActions.vue';

const ButtonStub = {
  name: 'Button',
  emits: ['click'],
  template: '<button data-testid="toggle" @click="$emit(\'click\')" />',
};

const DropdownMenuStub = {
  name: 'DropdownMenu',
  props: ['menuItems'],
  template: '<div data-testid="dropdown" />',
};

const mountComponent = () =>
  shallowMount(BulkAgentActions, {
    props: { selectedInboxes: [7] },
    global: {
      stubs: {
        Button: ButtonStub,
        DropdownMenu: DropdownMenuStub,
        Transition: false,
      },
      directives: { 'on-click-outside': {} },
    },
  });

describe('BulkAgentActions assignment gate (D-11)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isAssignmentGateEnabled.value = false;
  });

  it('omits the None item when the assignment gate is enabled', () => {
    isAssignmentGateEnabled.value = true;
    const wrapper = mountComponent();
    const { agentMenuItems: menuItems } = wrapper.vm.$.setupState;

    expect(menuItems.find(item => item.value === 'none')).toBeUndefined();
  });

  it('places the translated None item first when the gate is disabled', () => {
    const wrapper = mountComponent();
    const { agentMenuItems: menuItems } = wrapper.vm.$.setupState;

    expect(menuItems[0]).toMatchObject({
      value: 'none',
      label: 'Translated None',
    });
    expect(translate).toHaveBeenCalledWith('BULK_ACTION.NONE');
  });
});
