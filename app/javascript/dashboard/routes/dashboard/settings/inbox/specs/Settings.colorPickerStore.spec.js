import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import WidgetPreview from 'dashboard/modules/widget-preview/components/Widget.vue';
import Settings from '../Settings.vue';

// Mecanismo do aceite do bloco 0.9 (§2.2): "Editar a cor e sair sem salvar:
// `inboxes/getInbox` devolve o valor original".
//
// O defeito (D2): `<ColorPicker v-model="inbox.widget_color">` onde `inbox` e o
// proprio objeto devolvido por `inboxes/getInbox`. Arrastar o seletor gravava no
// store ANTES de qualquer dispatch, e o payload de salvamento lia de volta desse
// objeto ja sujo — o save "funcionava" sem nunca ter existido copia local.
//
// O teste e comportamental de proposito: nao olha se existe um campo chamado
// `channelWidgetColor`, olha o que o store devolve depois da edicao. Uma
// implementacao diferente que tambem pare de sujar o store passa igual.
vi.mock('dashboard/api/inboxHealth', () => ({
  default: { getHealthStatus: vi.fn().mockResolvedValue({ data: {} }) },
}));

const ORIGINAL_COLOR = '#1f93ff';
const EDITED_COLOR = '#ff00aa';

const buildStore = () => {
  // O objeto do state e devolvido por referencia, como o store de verdade faz —
  // e o que torna a mutacao reproduzivel. Clonar aqui esconderia o bug.
  const state = {
    inbox: {
      id: 1,
      name: 'Site da Acme',
      channel_type: 'Channel::WebWidget',
      widget_color: ORIGINAL_COLOR,
      website_url: 'https://acme.com.br',
      welcome_title: 'Ola',
      welcome_tagline: '',
      selected_feature_flags: [],
      reply_time: 'in_a_few_minutes',
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
      // Nao tem nada a ver com cor: o template le este getter para decidir se
      // mostra o banner de inbox duplicada do Instagram. Sem ele a montagem
      // estoura antes de chegar ao seletor, e a falha seria do harness, nao do
      // defeito que se quer medir.
      'inboxes/getInstagramInboxByInstagramId': () => () => null,
    },
  });
  store.dispatch = dispatch;

  return { store, state, dispatch };
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
      // Registrados globalmente no app, nao no harness. Stubados de proposito:
      // sem isso o Vue emite "Failed to resolve component" a cada montagem e o
      // ruido esconderia um erro de verdade.
      stubs: {
        // O seletor de cor mora no slot default de um SettingsAccordion, que por
        // sua vez esta num SettingsFieldSection. O stub automatico do
        // shallowMount nao renderiza slot, e sem estes dois o ColorPicker nunca
        // monta — a falha seria do harness, nao do defeito.
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
      // `v-on-clickaway` e diretiva global do app. Sem registrar, o Vue avisa
      // "Failed to resolve directive" a cada montagem.
      directives: { 'on-clickaway': () => {} },
    },
  });

const editColor = async wrapper => {
  const picker = wrapper.findComponent(ColorPicker);
  expect(picker.exists()).toBe(true);
  // E o que o v-model faz quando o admin arrasta o seletor.
  picker.vm.$emit('update:modelValue', EDITED_COLOR);
  await wrapper.vm.$nextTick();
  return picker;
};

describe('Settings.vue — ColorPicker nao suja o store (D2, bloco 0.9)', () => {
  it('editar a cor e sair sem salvar deixa inboxes/getInbox com o valor original', async () => {
    const { store, dispatch } = buildStore();
    const wrapper = mountSettings(store);

    await editColor(wrapper);

    // ACEITE: o store nao foi tocado.
    expect(store.getters['inboxes/getInbox'](1).widget_color).toBe(
      ORIGINAL_COLOR
    );
    // "sair sem salvar": nada subiu para o servidor.
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/updateInbox',
      expect.anything()
    );
  });

  it('a edicao nao se perde — o rascunho recebe a cor nova', async () => {
    // Sem esta asserção, o teste acima passaria tambem se o seletor estivesse
    // simplesmente morto. Ela separa "store protegido" de "picker quebrado".
    const { store } = buildStore();
    const wrapper = mountSettings(store);

    const picker = await editColor(wrapper);

    expect(picker.props('modelValue')).toBe(EDITED_COLOR);
  });

  it('o preview ao vivo ACOMPANHA a cor editada', async () => {
    // A regressao que a correcao nao pode introduzir. Parar de sujar o store sem
    // religar o preview trocaria um store sujo por uma tela que mente: o admin
    // arrasta o seletor e o preview continua na cor salva.
    const { store } = buildStore();
    const wrapper = mountSettings(store);

    await editColor(wrapper);

    const preview = wrapper.findComponent(WidgetPreview);
    expect(preview.exists()).toBe(true);
    expect(preview.props('color')).toBe(EDITED_COLOR);
  });

  it('salvar envia a cor editada, nao a original', async () => {
    const { store, dispatch } = buildStore();
    const wrapper = mountSettings(store);

    await editColor(wrapper);
    await wrapper.vm.updateInbox();

    const call = dispatch.mock.calls.find(
      ([action]) => action === 'inboxes/updateInbox'
    );
    expect(call).toBeDefined();
    expect(call[1].channel.widget_color).toBe(EDITED_COLOR);
  });
});
