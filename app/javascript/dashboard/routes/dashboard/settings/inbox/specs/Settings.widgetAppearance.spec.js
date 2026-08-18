import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Settings from '../Settings.vue';

// Mecanismo do aceite do bloco 3.18 (§2.2): "a aparencia sai do localStorage e vira configuracao".
//
// O defeito (D1): posicao, formato e texto do lancador viviam em `localStorage['widgetBubble_<id>']`,
// no navegador DO ADMIN. O admin A salvava, o admin B abria a mesma inbox e via o padrao de fabrica,
// e o site do cliente nunca via nada — a tela mostrava um valor que nao existia em lugar nenhum.
//
// O teste e comportamental: nao verifica se existe um campo chamado `storedWidgetAppearance`,
// verifica o que a tela LE (o que veio do servidor) e o que ela ENVIA ao salvar.
vi.mock('dashboard/api/inboxHealth', () => ({
  default: { getHealthStatus: vi.fn().mockResolvedValue({ data: {} }) },
}));

const STORED_APPEARANCE = {
  theme: 'dark',
  position: 'left',
  offset_x: 24,
  offset_y: 16,
  launcher_type: 'expanded_bubble',
  launcher_text: 'Fale com a gente',
  hide_bubble: false,
  panel_style: 'flat',
  launcher_icon: 'agent_photo',
};

const buildStore = (widgetAppearance = STORED_APPEARANCE) => {
  const state = {
    inbox: {
      id: 1,
      name: 'Site da Acme',
      channel_type: 'Channel::WebWidget',
      widget_color: '#2dc46f',
      website_url: 'https://acme.com.br',
      welcome_title: 'Ola',
      welcome_tagline: '',
      selected_feature_flags: [],
      reply_time: 'in_a_few_minutes',
      additional_attributes: { widget_appearance: widgetAppearance },
    },
  };

  const dispatch = vi.fn().mockResolvedValue({});

  const store = createStore({
    state,
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'globalConfig/isOnChatwootCloud': () => false,
      'inboxes/getUIFlags': () => ({ isUpdating: false, isCreating: false }),
      'portals/allPortals': () => [],
      'inboxes/getInbox': currentState => () => currentState.inbox,
      'agents/getAgents': () => [],
      'teams/getTeams': () => [],
      'labels/getLabels': () => [],
      'inboxes/getInstagramInboxByInstagramId': () => () => null,
    },
  });
  store.dispatch = dispatch;

  return { store, dispatch };
};

const mountSettings = store =>
  shallowMount(Settings, {
    global: {
      plugins: [store],
      mocks: {
        $t: key => key,
        $route: {
          name: 'settings_inbox_show',
          params: { inboxId: '1' },
          query: {},
        },
      },
      stubs: {
        SettingsAccordion: {
          name: 'SettingsAccordion',
          template: '<div><slot /></div>',
        },
        SettingsFieldSection: {
          name: 'SettingsFieldSection',
          template: '<div><slot /></div>',
        },
        'woot-code': true,
        'woot-input': true,
        'woot-avatar-uploader': true,
        'woot-loading-state': true,
        'woot-color-picker': true,
        'woot-tabs': true,
        'woot-tabs-item': true,
        'woot-modal': true,
        'woot-modal-header': true,
        'woot-confirm-modal': true,
      },
      directives: { 'on-clickaway': () => {} },
    },
  });

const savedPayload = dispatch => {
  const call = dispatch.mock.calls.find(
    ([action]) => action === 'inboxes/updateInbox'
  );
  expect(call).toBeDefined();
  return call[1];
};

describe('Settings.vue — a aparencia vem do servidor, nao do localStorage (D1, bloco 3.18)', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('le a posicao gravada no servidor, sem nada no localStorage deste navegador', () => {
    // E o cenario do admin B: navegador limpo, mesma inbox.
    const { store } = buildStore();
    const wrapper = mountSettings(store);

    expect(wrapper.vm.widgetBubblePosition).toBe('left');
    expect(wrapper.vm.widgetBubbleType).toBe('expanded_bubble');
    expect(wrapper.vm.widgetBubbleLauncherTitle).toBe('Fale com a gente');
  });

  it('cai no padrao de fabrica quando o servidor nao tem aparencia gravada', () => {
    // `null`, e nao `undefined`: passar undefined reativaria o valor padrao do parametro.
    const { store } = buildStore(null);
    const wrapper = mountSettings(store);

    expect(wrapper.vm.widgetBubblePosition).toBe('right');
    expect(wrapper.vm.widgetBubbleType).toBe('standard');
    expect(wrapper.vm.widgetBubbleLauncherTitle).toBe('');
  });

  it('salvar envia a aparencia editada dentro de additional_attributes', async () => {
    const { store, dispatch } = buildStore();
    const wrapper = mountSettings(store);

    wrapper.vm.widgetBubblePosition = 'right';
    wrapper.vm.widgetBubbleLauncherTitle = 'Precisa de ajuda?';
    await wrapper.vm.updateInbox();

    const appearance =
      savedPayload(dispatch).additional_attributes.widget_appearance;
    expect(appearance.position).toBe('right');
    expect(appearance.launcher_text).toBe('Precisa de ajuda?');
    expect(appearance.launcher_type).toBe('expanded_bubble');
  });

  it('NAO apaga os campos de aparencia que esta tela ainda nao edita', async () => {
    // O merge do servidor e raso (`inboxes_controller.rb:52-56`): `widget_appearance` e substituido
    // inteiro. Enviar so os tres campos desta tela apagaria tema, offsets, estilo e icone — que e
    // exatamente a classe de defeito "o formulario reenvia o objeto e o servidor sobrescreve".
    const { store, dispatch } = buildStore();
    const wrapper = mountSettings(store);

    wrapper.vm.widgetBubblePosition = 'right';
    await wrapper.vm.updateInbox();

    const appearance =
      savedPayload(dispatch).additional_attributes.widget_appearance;
    expect(appearance.theme).toBe('dark');
    expect(appearance.offset_x).toBe(24);
    expect(appearance.offset_y).toBe(16);
    expect(appearance.panel_style).toBe('flat');
    expect(appearance.launcher_icon).toBe('agent_photo');
  });

  it('nao escreve mais nada no localStorage ao salvar', async () => {
    const { store } = buildStore();
    const wrapper = mountSettings(store);

    wrapper.vm.widgetBubblePosition = 'right';
    await wrapper.vm.updateInbox();

    expect(window.localStorage.getItem('widgetBubble_1')).toBeNull();
    expect(Object.keys(window.localStorage)).toHaveLength(0);
  });
});
