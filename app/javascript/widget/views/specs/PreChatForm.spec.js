import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import PreChatFormView from '../PreChatForm.vue';
import { emitter } from 'shared/helpers/mitt';
import { getters as conversationGetters } from 'widget/store/modules/conversation/getters';
import { mutations as conversationMutations } from 'widget/store/modules/conversation/mutations';
import { actions as conversationActions } from 'widget/store/modules/conversation/actions';

global.chatwootWebChannel = {
  preChatFormEnabled: true,
  preChatFormOptions: { pre_chat_fields: [], pre_chat_message: '' },
};

describe('PreChatForm view', () => {
  let createConversation;
  let setCustomAttributes;
  let updateContact;
  let store;

  beforeEach(() => {
    createConversation = vi.fn();
    setCustomAttributes = vi.fn();
    updateContact = vi.fn();
    store = createStore({
      modules: {
        conversation: {
          namespaced: true,
          actions: { createConversation, clearConversations: vi.fn() },
        },
        conversationAttributes: {
          namespaced: true,
          actions: { clearConversationAttributes: vi.fn() },
        },
        contacts: {
          namespaced: true,
          actions: { setCustomAttributes, update: updateContact },
        },
      },
    });
  });

  const mountView = () =>
    shallowMount(PreChatFormView, { global: { plugins: [store] } });

  it('sends contact custom attributes with the conversation create request', async () => {
    const wrapper = mountView();
    wrapper.vm.onSubmit({
      fullName: 'John',
      emailAddress: 'john@example.com',
      message: 'hey',
      contactCustomAttributes: { cpf: '123.456.789-09' },
      conversationCustomAttributes: { order_id: '12345' },
    });
    await flushPromises();

    expect(createConversation).toHaveBeenCalledWith(expect.anything(), {
      fullName: 'John',
      emailAddress: 'john@example.com',
      message: 'hey',
      phoneNumber: undefined,
      customAttributes: { order_id: '12345' },
      contactCustomAttributes: { cpf: '123.456.789-09' },
    });
    // attributes ride along in the create request itself; a separate call
    // would race the contact merge on the server and write to a destroyed
    // contact
    expect(setCustomAttributes).not.toHaveBeenCalled();
  });

  it('sends contact custom attributes along with the contact update for campaigns', async () => {
    const wrapper = mountView();
    wrapper.vm.onSubmit({
      fullName: 'John',
      emailAddress: 'john@example.com',
      phoneNumber: null,
      activeCampaignId: 42,
      contactCustomAttributes: { cpf: '123.456.789-09' },
      conversationCustomAttributes: {},
    });
    await flushPromises();

    expect(updateContact).toHaveBeenCalledWith(expect.anything(), {
      user: {
        email: 'john@example.com',
        name: 'John',
        phone_number: null,
        custom_attributes: { cpf: '123.456.789-09' },
      },
    });
    expect(createConversation).not.toHaveBeenCalled();
    expect(setCustomAttributes).not.toHaveBeenCalled();
  });

  // ── Bloco 5.08 ────────────────────────────────────────────────────────────
  //
  // O coletor de origem entrega os `last_*` por `conversation/setCustomAttributes`, que
  // enquanto NAO ha conversa guarda em `pendingCustomAttributes` (store/conversation/
  // actions.js). Sem pre-chat, `sendMessage` os leva junto da primeira mensagem; COM
  // pre-chat, a conversa nasce por outro caminho — este — e a origem morria em silencio.
  //
  // O modulo abaixo e o REAL (state, getters, mutations e a action `clearConversations`):
  // um dubles de `clearConversations` esconderia o defeito, porque a mutation de verdade
  // ZERA `pendingCustomAttributes` — e ela roda antes do `createConversation`. E por isso
  // que a leitura tem de acontecer ANTES da limpeza, e nao dentro da action de criacao.
  describe('a origem que o coletor guardou antes de existir conversa', () => {
    const ORIGEM = {
      last_utm_source: 'google',
      last_gclid: 'CjwKC-abc123',
    };

    const montarComOrigem = () => {
      const criar = vi.fn();
      const storeReal = createStore({
        modules: {
          conversation: {
            namespaced: true,
            state: {
              conversations: {},
              meta: { userLastSeenAt: undefined },
              uiFlags: {},
              lastMessageId: null,
              pendingCustomAttributes: { ...ORIGEM },
              pendingLabels: [],
            },
            getters: conversationGetters,
            mutations: conversationMutations,
            actions: {
              clearConversations: conversationActions.clearConversations,
              createConversation: criar,
            },
          },
          conversationAttributes: {
            namespaced: true,
            actions: { clearConversationAttributes: vi.fn() },
          },
          contacts: {
            namespaced: true,
            actions: { setCustomAttributes: vi.fn(), update: vi.fn() },
          },
        },
      });
      const wrapper = shallowMount(PreChatFormView, {
        global: { plugins: [storeReal] },
      });
      return { wrapper, criar, storeReal };
    };

    it('viaja no mesmo POST que cria a conversa', async () => {
      const { wrapper, criar } = montarComOrigem();

      wrapper.vm.onSubmit({
        fullName: 'John',
        emailAddress: 'john@example.com',
        message: 'hey',
        contactCustomAttributes: {},
        conversationCustomAttributes: { order_id: '12345' },
      });
      await flushPromises();

      expect(criar).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          customAttributes: { ...ORIGEM, order_id: '12345' },
        })
      );
    });

    // O que o visitante DIGITOU vence: se o site batizasse um campo do pre-chat com o nome
    // de uma chave de origem, o valor digitado e o mais recente e o mais verdadeiro.
    it('cede a chave para o campo que o visitante digitou', async () => {
      const { wrapper, criar } = montarComOrigem();

      wrapper.vm.onSubmit({
        fullName: 'John',
        message: 'hey',
        conversationCustomAttributes: { last_utm_source: 'digitado' },
      });
      await flushPromises();

      expect(criar).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          customAttributes: {
            last_utm_source: 'digitado',
            last_gclid: 'CjwKC-abc123',
          },
        })
      );
    });

    it('viaja tambem quando a conversa nasce de uma campanha', async () => {
      const { wrapper } = montarComOrigem();
      const emitido = vi.spyOn(emitter, 'emit');

      wrapper.vm.onSubmit({
        fullName: 'John',
        emailAddress: 'john@example.com',
        activeCampaignId: 42,
        contactCustomAttributes: {},
        conversationCustomAttributes: { order_id: '12345' },
      });
      await flushPromises();

      expect(emitido).toHaveBeenCalledWith('execute-campaign', {
        campaignId: 42,
        customAttributes: { ...ORIGEM, order_id: '12345' },
      });
      emitido.mockRestore();
    });
  });
});
