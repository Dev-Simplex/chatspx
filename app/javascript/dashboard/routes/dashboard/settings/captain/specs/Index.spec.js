import { nextTick } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises, shallowMount } from '@vue/test-utils';
import Index from '../Index.vue';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';

const { alertSpy, routerReplace } = vi.hoisted(() => ({
  alertSpy: vi.fn(),
  routerReplace: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useRouter: () => ({
      replace: routerReplace,
    }),
  };
});

vi.mock('dashboard/composables', () => ({
  useAlert: alertSpy,
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
  }),
}));

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    captainEnabled: { value: true },
  }),
}));

const SettingsLayoutStub = {
  name: 'SettingsLayout',
  template: '<div><slot name="header" /><slot name="body" /></div>',
};

const SectionLayoutStub = {
  name: 'SectionLayout',
  template: '<section><slot /></section>',
};

const BaseSettingsHeaderStub = {
  name: 'BaseSettingsHeader',
  template: '<header />',
};

const ModelSelectorStub = {
  name: 'ModelSelector',
  template: '<div />',
};

const FeatureToggleStub = {
  name: 'FeatureToggle',
  template: '<div />',
};

const mountComponent = () => {
  const pinia = createPinia();
  setActivePinia(pinia);

  const store = useCaptainConfigStore();
  store.$patch({
    uiFlags: { isFetching: false },
    llmConnection: {
      provider: 'openai',
      configured: true,
      maskedApiKey: 'sk-t***1234',
      updatedAt: '2026-02-19T10:00:00.000Z',
    },
  });

  vi.spyOn(store, 'fetch').mockResolvedValue();
  vi.spyOn(store, 'updatePreferences').mockResolvedValue();

  const wrapper = shallowMount(Index, {
    global: {
      plugins: [pinia],
      stubs: {
        SettingsLayout: SettingsLayoutStub,
        BaseSettingsHeader: BaseSettingsHeaderStub,
        SectionLayout: SectionLayoutStub,
        ModelSelector: ModelSelectorStub,
        FeatureToggle: FeatureToggleStub,
      },
    },
  });

  return { wrapper, store };
};

describe('Captain settings Index.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    routerReplace.mockClear();
  });

  it('renders OpenAI connection block with configured status', () => {
    const { wrapper } = mountComponent();

    expect(
      wrapper.find('[data-testid="captain-openai-connection-card"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="captain-openai-status"]').text()).toBe(
      'CAPTAIN_SETTINGS.OPENAI_CONNECTION.STATUS_CONFIGURED'
    );
  });

  it('saves account OpenAI key from settings', async () => {
    const { wrapper, store } = mountComponent();

    const input = wrapper.find('[data-testid="captain-openai-api-key-input"]');
    await input.setValue('  sk-new-account-key  ');

    await wrapper
      .find('[data-testid="captain-openai-save-key"]')
      .trigger('click');

    expect(store.updatePreferences).toHaveBeenCalledWith({
      llm_connection: {
        openai_api_key: 'sk-new-account-key',
      },
    });
    expect(alertSpy).toHaveBeenCalledWith(
      'CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.SUCCESS'
    );
  });

  it('removes account OpenAI key from settings', async () => {
    const { wrapper, store } = mountComponent();

    await wrapper
      .find('[data-testid="captain-openai-remove-key"]')
      .trigger('click');

    expect(store.updatePreferences).toHaveBeenCalledWith({
      llm_connection: {
        remove_api_key: true,
      },
    });
    expect(alertSpy).toHaveBeenCalledWith(
      'CAPTAIN_SETTINGS.OPENAI_CONNECTION.API.SUCCESS'
    );

    await nextTick();
  });

  it('shows backend error message when OpenAI key is invalid', async () => {
    const { wrapper, store } = mountComponent();
    store.updatePreferences.mockRejectedValueOnce({
      response: {
        data: {
          message:
            'A chave da OpenAI é inválida. Verifique a chave e tente novamente.',
        },
      },
    });

    const input = wrapper.find('[data-testid="captain-openai-api-key-input"]');
    await input.setValue('sk-invalid-key');
    await wrapper
      .find('[data-testid="captain-openai-save-key"]')
      .trigger('click');
    await flushPromises();

    expect(alertSpy).toHaveBeenCalledWith(
      'A chave da OpenAI é inválida. Verifique a chave e tente novamente.'
    );
  });
});
