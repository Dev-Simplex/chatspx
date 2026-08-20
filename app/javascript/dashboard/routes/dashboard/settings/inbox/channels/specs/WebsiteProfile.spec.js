import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Website from '../Website.vue';

vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 'ltr' }),
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
}));

vi.mock('../../../../index', () => ({ default: { replace: vi.fn() } }));

const [i18n] = config.global.plugins;

afterEach(() => {
  i18n.global.locale.value = 'en';
});

const build = () => {
  i18n.global.locale.value = 'pt_BR';
  const dispatch = vi.fn().mockResolvedValue({ id: 9 });
  const store = createStore({
    getters: { 'inboxes/getUIFlags': () => ({ isCreating: false }) },
  });
  store.dispatch = dispatch;

  const wrapper = mount(Website, {
    global: {
      plugins: [store],
      stubs: {
        PageHeader: true,
        GreetingsEditor: true,
        Editor: true,
        'woot-color-picker': true,
        'woot-loading-state': true,
      },
    },
  });
  return { wrapper, dispatch };
};

describe('wizard de criação — a pergunta do perfil', () => {
  it('pergunta para que serve a caixa, sem default pré-selecionado', () => {
    const { wrapper } = build();

    expect(wrapper.text()).toContain('Para que serve esta caixa?');
    expect(
      wrapper.find('[data-testid="profile-support"] input').element.checked
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="profile-marketing"] input').element.checked
    ).toBe(false);
  });

  it('sem responder, não dá para criar a caixa', async () => {
    const { wrapper } = build();
    const inputs = wrapper.findAll('input[type="text"]');
    await inputs[0].setValue('Site novo');
    await inputs[1].setValue('https://simplex.com.br');

    expect(wrapper.find('button[type="submit"]').attributes('disabled')).toBe(
      ''
    );

    await wrapper
      .find('[data-testid="profile-marketing"] input')
      .trigger('change');

    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('o perfil escolhido vai no create, em additional_attributes', async () => {
    const { wrapper, dispatch } = build();
    const inputs = wrapper.findAll('input[type="text"]');
    await inputs[0].setValue('Site novo');
    await inputs[1].setValue('https://simplex.com.br');
    await wrapper
      .find('[data-testid="profile-marketing"] input')
      .trigger('change');

    await wrapper.find('form').trigger('submit');

    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createWebsiteChannel',
      expect.objectContaining({
        additional_attributes: { widget_profile: 'marketing' },
      })
    );
  });
});
