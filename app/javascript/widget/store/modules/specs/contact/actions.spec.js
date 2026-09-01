import { API } from 'widget/helpers/axios';
import { sendMessage } from 'widget/helpers/utils';
import { actions } from '../../contacts';

const commit = vi.fn();
const dispatch = vi.fn();

vi.mock('widget/helpers/axios');
vi.mock('widget/helpers/utils', () => ({
  sendMessage: vi.fn(),
}));

describe('#actions', () => {
  describe('#setUser', () => {
    it('sends correct actions if contact object is refreshed ', async () => {
      const user = {
        email: 'thoma@sphadikam.com',
        name: 'Adu Thoma',
        avatar_url: '',
      };
      vi.spyOn(API, 'patch').mockResolvedValue({
        data: { widget_auth_token: 'token' },
      });
      await actions.setUser({ commit, dispatch }, { identifier: 1, user });
      expect(sendMessage.mock.calls).toEqual([
        [{ data: { widgetAuthToken: 'token' }, event: 'setAuthCookie' }],
      ]);
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([
        ['get'],
        ['conversation/clearConversations', {}, { root: true }],
        ['conversation/fetchOldConversations', {}, { root: true }],
        ['conversationAttributes/getAttributes', {}, { root: true }],
      ]);
    });

    it('sends correct actions if identifierHash is passed ', async () => {
      const user = {
        email: 'thoma@sphadikam.com',
        name: 'Adu Thoma',
        avatar_url: '',
        identifier_hash: '12345',
      };
      vi.spyOn(API, 'patch').mockResolvedValue({ data: { id: 1 } });
      await actions.setUser({ commit, dispatch }, { identifier: 1, user });
      expect(sendMessage.mock.calls).toEqual([]);
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([
        ['get'],
        ['conversation/clearConversations', {}, { root: true }],
        ['conversation/fetchOldConversations', {}, { root: true }],
        ['conversationAttributes/getAttributes', {}, { root: true }],
      ]);
    });

    it('does not call sendMessage if contact object is not refreshed ', async () => {
      const user = {
        email: 'thoma@sphadikam.com',
        name: 'Adu Thoma',
        avatar_url: '',
      };
      API.patch.mockResolvedValue({ data: { id: 1 } });
      await actions.setUser({ commit, dispatch }, { identifier: 1, user });
      expect(sendMessage.mock.calls).toEqual([]);
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([['get']]);
    });
  });

  describe('#update', () => {
    it('sends correct actions', async () => {
      const user = {
        email: 'thoma@sphadikam.com',
        name: 'Adu Thoma',
        avatar_url: '',
        identifier_hash: 'random_hex_identifier_hash',
      };
      API.patch.mockResolvedValue({ data: { id: 1 } });
      await actions.update({ commit, dispatch }, { identifier: 1, user });
      expect(commit.mock.calls).toEqual([]);
      expect(dispatch.mock.calls).toEqual([['get']]);
    });
  });

  // Bloco 5.19 — a credencial dentro do painel.
  //
  // O `set_user` nao e a unica porta: o pre-chat com campanha (`PreChatForm.vue`) escreve pelo
  // `PATCH /widget/contact`, que e a action `update` daqui. O servidor passou a marcar
  // `hmac_verified` tambem nessa rota — mas so marca se a prova CHEGAR, e ela so chega se o
  // painel lembrar do token que o host mandou na identificacao.
  describe('#5.19 — o identity_token dentro do painel', () => {
    beforeEach(() => {
      commit.mockClear();
      dispatch.mockClear();
      API.patch.mockResolvedValue({ data: { id: 1 } });
    });

    it('setUser repassa a credencial no corpo da requisicao', async () => {
      await actions.setUser(
        { commit, dispatch },
        {
          identifier: 'CRM-4711',
          user: { name: 'Ana', identity_token: 'jwt.do.cliente' },
        }
      );

      expect(API.patch.mock.calls[0][1].identity_token).toBe('jwt.do.cliente');
    });

    it('e GUARDA o token, porque a proxima porta e outra rota', async () => {
      await actions.setUser(
        { commit, dispatch },
        {
          identifier: 'CRM-4711',
          user: { name: 'Ana', identity_token: 'jwt.do.cliente' },
        }
      );

      expect(commit.mock.calls).toEqual([
        ['SET_IDENTITY_TOKEN', 'jwt.do.cliente'],
      ]);
    });

    it('o update do pre-chat leva o token que a identificacao deixou guardado', async () => {
      const state = { currentUser: {}, identityToken: 'jwt.do.cliente' };

      await actions.update(
        { commit, dispatch, state },
        { user: { email: 'ana@exemplo.com.br' } }
      );

      expect(API.patch.mock.calls[0][1]).toEqual({
        email: 'ana@exemplo.com.br',
        identity_token: 'jwt.do.cliente',
      });
    });

    // A CONDICAO RUIM FORCADA: sem token guardado o corpo nao pode ganhar uma chave de credencial
    // vazia. "Sem credencial" e "credencial vazia" sao dois fatos diferentes para o servidor.
    it('sem token guardado, o update sai exatamente como antes deste bloco', async () => {
      await actions.update(
        { commit, dispatch, state: { currentUser: {} } },
        { user: { email: 'ana@exemplo.com.br' } }
      );

      expect(API.patch.mock.calls[0][1]).toEqual({
        email: 'ana@exemplo.com.br',
      });
    });
  });
});
