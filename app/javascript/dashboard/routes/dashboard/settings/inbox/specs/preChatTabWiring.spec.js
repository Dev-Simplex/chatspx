import { shallowMount } from '@vue/test-utils';
import Settings from '../Settings.vue';
import PreChatPage from '../widget/prechat/PreChatPage.vue';
import PreChatFormSettings from '../PreChatForm/Settings.vue';

/**
 * Bloco 3.14 — a aba `pre-chat-form` monta a TELA 3.
 *
 * Este arquivo existe porque o resto da suíte do pré-chat monta `PreChatPage`
 * DIRETO. Setenta testes verdes provavam que o componente funciona e nenhum
 * provava que alguém o coloca na tela — e não colocava: a aba renderizava o
 * `PreChatForm/Settings.vue`, e nenhum administrador tinha como chegar na
 * Tela 3. "O componente passa" e "o recurso existe para o cliente" são duas
 * afirmações diferentes, e só a segunda é o bloco.
 *
 * `shallowMount` de propósito: o que está sob teste é a decisão de QUAL
 * componente a aba monta e COM QUE contrato. Montar a árvore inteira arrastaria
 * meia dúzia de módulos do store para dentro de uma asserção sobre uma linha de
 * template.
 */

const inboxDeSite = () => ({
  id: 7,
  name: 'Site da Simplex',
  channel_type: 'Channel::WebWidget',
  provider: '',
  website_token: 'tok',
  pre_chat_form_enabled: true,
  pre_chat_form_options: { pre_chat_message: '', pre_chat_fields: [] },
  additional_attributes: {},
  selected_feature_flags: [],
});

const montar = ({ query = {} } = {}) => {
  const inbox = inboxDeSite();
  const store = {
    getters: {
      getCurrentAccountId: 1,
      'accounts/isFeatureEnabledonAccount': () => false,
      'globalConfig/isOnChatwootCloud': false,
      'inboxes/getUIFlags': {},
      'portals/allPortals': [],
      'inboxes/getInbox': () => inbox,
      'inboxes/getInstagramInboxByInstagramId': () => undefined,
      'attributes/getAttributes': [],
    },
    dispatch: vi.fn().mockResolvedValue({}),
  };

  return shallowMount(Settings, {
    global: {
      mocks: {
        $store: store,
        $route: {
          params: { accountId: '1', inboxId: '7', tab: 'pre-chat-form' },
          query,
        },
        $router: { push: vi.fn(), replace: vi.fn() },
      },
      stubs: { RouterLink: true },
    },
  });
};

describe('aba pré-chat — quem a aba monta', () => {
  it('monta a Tela 3, e não a tela antiga', async () => {
    const wrapper = montar();
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.selectedTabKey).toBe('pre-chat-form');
    expect(wrapper.findComponent(PreChatPage).exists()).toBe(true);
    expect(wrapper.findComponent(PreChatFormSettings).exists()).toBe(false);
  });

  it('entrega à Tela 3 o contrato que ela pede: `inboxId`', async () => {
    const wrapper = montar();
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent(PreChatPage).props('inboxId')).toBe(7);
  });

  // `onTabChange` procura `requestLeave` na tela montada. Sem o `ref` com este
  // nome exato a lista fica vazia, e a troca de aba leva o rascunho embora sem
  // perguntar — em silêncio, que é o pior jeito de perder dez campos.
  //
  // O dublê é uma função que devolve booleano porque é essa a forma REAL de
  // `useUnsavedChangesGuard#requestLeave` (que `PreChatPage.spec.js` exercita
  // de verdade). Aqui o que está sob teste é o outro lado: `Settings.vue`
  // consulta a Tela 3, e obedece.
  const comGuarda = async retorno => {
    const wrapper = montar();
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();
    const requestLeave = vi.fn(acao => {
      if (retorno) acao();
      return retorno;
    });
    wrapper.vm.$refs.preChatPage.requestLeave = requestLeave;
    return { wrapper, requestLeave };
  };

  it('a troca de aba SEGURA quando a Tela 3 tem rascunho pendente', async () => {
    const { wrapper, requestLeave } = await comGuarda(false);
    const antes = wrapper.vm.selectedTabIndex;

    wrapper.vm.onTabChange(0);

    expect(requestLeave).toHaveBeenCalled();
    expect(wrapper.vm.selectedTabIndex).toBe(antes);
  });

  it('a troca de aba PASSA quando a Tela 3 está limpa', async () => {
    const { wrapper, requestLeave } = await comGuarda(true);

    wrapper.vm.onTabChange(0);

    expect(requestLeave).toHaveBeenCalled();
    expect(wrapper.vm.selectedTabIndex).toBe(0);
  });

  it('o legado continua alcançável — não foi apagado, é decisão do dono', async () => {
    const wrapper = montar({ query: { prechat: 'legacy' } });
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent(PreChatFormSettings).exists()).toBe(true);
    expect(wrapper.findComponent(PreChatPage).exists()).toBe(false);
  });

  it('sem o parâmetro na URL, o padrão é a Tela 3', async () => {
    const wrapper = montar({ query: { prechat: 'qualquer-outra-coisa' } });
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent(PreChatPage).exists()).toBe(true);
  });
});
