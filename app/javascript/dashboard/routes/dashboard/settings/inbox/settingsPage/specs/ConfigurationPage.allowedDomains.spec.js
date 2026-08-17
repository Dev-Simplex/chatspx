import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ConfigurationPage from '../ConfigurationPage.vue';

// Mecanismo do aceite do bloco 0.8, item 3 (D8): "a tela diz o que acontece com
// dominio vazio". O defeito e de OMISSAO — a tela calava — entao o teste tem de
// olhar o texto renderizado, nao um valor interno.
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({ runEmbeddedSignup: vi.fn() }),
}));

const WARNING_KEYS = [
  'INBOX_WIDGET.CONFIGURATION.ALLOWED_DOMAINS.EMPTY_WARNING.TITLE',
  'INBOX_WIDGET.CONFIGURATION.ALLOWED_DOMAINS.EMPTY_WARNING.BODY',
  'INBOX_WIDGET.CONFIGURATION.ALLOWED_DOMAINS.EMPTY_WARNING.ACTION_HINT',
];

// O aviso mora no slot #editor do SettingsToggleSection. O stub automatico do
// shallowMount nao renderiza slot nomeado, entao o aviso ficaria invisivel para
// o teste mesmo estando na tela. Este stub renderiza o slot e nada mais; Banner
// fica real (`false`) para que `text()` veja o conteudo de verdade.
const STUBS = {
  SettingsToggleSection: {
    name: 'SettingsToggleSection',
    template: '<div><slot name="editor" /></div>',
  },
  Banner: false,
  // `woot-code` e `woot-input` sao registrados globalmente no app, nao no
  // harness de teste. Stubados aqui de proposito: sem isso o Vue emite
  // "Failed to resolve component" em toda montagem e o ruido esconderia um erro
  // de verdade. Nao e defeito do componente sob teste.
  'woot-code': true,
  'woot-input': true,
};

const buildStore = () =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'globalConfig/isOnChatwootCloud': () => false,
    },
  });

const mountPage = allowedDomains =>
  shallowMount(ConfigurationPage, {
    props: {
      inbox: {
        id: 7,
        channel_type: 'Channel::WebWidget',
        allowed_domains: allowedDomains,
        selected_feature_flags: [],
      },
    },
    global: {
      plugins: [buildStore()],
      mocks: { $t: key => key },
      stubs: STUBS,
    },
  });

describe('ConfigurationPage — aviso de allowed_domains vazio (D8)', () => {
  it('avisa, com a consequencia escrita, quando allowed_domains esta vazio', () => {
    const wrapper = mountPage('');
    const banner = wrapper.findComponent(Banner);

    expect(banner.exists()).toBe(true);
    // amber: e aviso, nao informacao neutra nem erro fatal.
    expect(banner.props('color')).toBe('amber');
    // As tres partes precisam estar na tela: o que acontece, por que importa e
    // o que fazer. So o titulo nao diz a consequencia.
    WARNING_KEYS.forEach(key => {
      expect(banner.text()).toContain(key);
    });
  });

  it('avisa quando o campo tem so espacos em branco', () => {
    // `allowed_domains.blank?` do Ruby trata "   " como vazio e apaga o
    // X-Frame-Options; a tela precisa concordar com o servidor.
    expect(mountPage('   ').findComponent(Banner).exists()).toBe(true);
  });

  it('nao avisa quando ha dominio gravado', () => {
    expect(
      mountPage('https://exemplo.com.br').findComponent(Banner).exists()
    ).toBe(false);
  });

  it('nao avisa em inbox que nao e web widget', () => {
    const wrapper = shallowMount(ConfigurationPage, {
      props: {
        inbox: {
          id: 8,
          channel_type: 'Channel::Api',
          allowed_domains: '',
          selected_feature_flags: [],
        },
      },
      global: {
        plugins: [buildStore()],
        mocks: { $t: key => key },
        stubs: { Banner: false },
      },
    });

    expect(wrapper.findComponent(Banner).exists()).toBe(false);
  });
});
