import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Website from '../Website.vue';

// Mecanismo do aceite do bloco 0.8, item 2 (D11), lado da TELA: "inbox criada
// por tela e por API nasce com a MESMA cor".
//
// O lado da API esta em `spec/models/channel/web_widget_default_color_spec.rb`,
// e os dois arquivos asseveram o MESMO literal — se alguem mudar so um lado, o
// outro fica vermelho. Aqui a asserção olha o payload que sai para o servidor,
// nao o dado interno do componente: o que define a cor da inbox e o que sobe.

// O componente importa o roteador real do dashboard so para navegar depois de
// criar. Mockado para o teste nao carregar o mapa de rotas inteiro.
// Cinco niveis, nao quatro: `vi.mock` resolve relativo a ESTE arquivo (que esta
// em `channels/specs/`), enquanto o import do componente parte de `channels/`.
// Com quatro o mock aponta para outro modulo, nao pega, e o roteador de verdade
// sobe reclamando de param invalido.
vi.mock('../../../../../index', () => ({
  default: { replace: vi.fn() },
}));

const buildStore = dispatch =>
  createStore({
    getters: {
      'inboxes/getUIFlags': () => ({ isCreating: false }),
    },
    actions: {
      'inboxes/createWebsiteChannel': dispatch,
    },
  });

const mountScreen = dispatch =>
  shallowMount(Website, {
    global: {
      plugins: [buildStore(dispatch)],
      mocks: { $t: key => key },
      // Registrados globalmente no app, nao no harness de teste. Stubados de
      // proposito: sem isso o Vue emite "Failed to resolve component" em toda
      // montagem e o ruido esconderia um erro de verdade.
      stubs: { 'woot-color-picker': true, 'woot-loading-state': true },
    },
  });

describe('Website.vue — cor default da inbox criada pela tela (D11)', () => {
  it('sobe o verde da marca ChatSPX quando o admin nao mexe no seletor', async () => {
    const dispatch = vi.fn().mockResolvedValue({ id: 42 });
    const wrapper = mountScreen(dispatch);

    wrapper.vm.inboxName = 'Site da Acme';
    wrapper.vm.channelWebsiteUrl = 'https://acme.com.br';
    await wrapper.vm.createChannel();

    expect(dispatch).toHaveBeenCalledTimes(1);
    const payload = dispatch.mock.calls[0][1];
    expect(payload.channel.widget_color).toBe('#2dc46f');
  });

  it('sobe a cor escolhida pelo admin, sem o default passar por cima', async () => {
    const dispatch = vi.fn().mockResolvedValue({ id: 43 });
    const wrapper = mountScreen(dispatch);

    wrapper.vm.inboxName = 'Site da Acme';
    wrapper.vm.channelWebsiteUrl = 'https://acme.com.br';
    wrapper.vm.channelWidgetColor = '#ff00aa';
    await wrapper.vm.createChannel();

    expect(dispatch.mock.calls[0][1].channel.widget_color).toBe('#ff00aa');
  });
});
