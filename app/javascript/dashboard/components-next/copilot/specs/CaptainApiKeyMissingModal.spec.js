import { shallowMount } from '@vue/test-utils';
import CaptainApiKeyMissingModal from '../CaptainApiKeyMissingModal.vue';

const { pushSpy } = vi.hoisted(() => ({
  pushSpy: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: pushSpy,
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const DialogStub = {
  name: 'Dialog',
  props: [
    'title',
    'description',
    'confirmButtonLabel',
    'showCancelButton',
    'cancelButtonLabel',
  ],
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
  template: `
    <div>
      <p data-testid="title">{{ title }}</p>
      <p data-testid="description">{{ description }}</p>
      <button data-testid="confirm" @click="$emit('confirm')">
        {{ confirmButtonLabel }}
      </button>
      <button data-testid="close" @click="$emit('close')">
        {{ cancelButtonLabel }}
      </button>
      <span data-testid="show-cancel">{{ showCancelButton }}</span>
    </div>
  `,
};

describe('CaptainApiKeyMissingModal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('routes admin to Captain settings on confirm', async () => {
    const wrapper = shallowMount(CaptainApiKeyMissingModal, {
      props: {
        isAdmin: true,
        accountId: 3,
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await wrapper.find('[data-testid="confirm"]').trigger('click');

    expect(pushSpy).toHaveBeenCalledWith({
      name: 'agents_settings',
      params: { accountId: 3 },
    });
  });

  it('does not route non-admin user on confirm', async () => {
    const wrapper = shallowMount(CaptainApiKeyMissingModal, {
      props: {
        isAdmin: false,
        accountId: 3,
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await wrapper.find('[data-testid="confirm"]').trigger('click');

    expect(pushSpy).not.toHaveBeenCalled();
  });

  it('emits close when dialog closes', async () => {
    const wrapper = shallowMount(CaptainApiKeyMissingModal, {
      props: {
        isAdmin: true,
        accountId: 3,
      },
      global: {
        stubs: {
          Dialog: DialogStub,
        },
      },
    });

    await wrapper.find('[data-testid="close"]').trigger('click');

    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
