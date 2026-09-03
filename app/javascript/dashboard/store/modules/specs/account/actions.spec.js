import axios from 'axios';
import { actions, getters } from '../../accounts';
import * as types from '../../../mutation-types';

const accountData = {
  id: 1,
  name: 'Company one',
  locale: 'en',
};

const newAccountInfo = {
  accountName: 'Company two',
};

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({ data: accountData });
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isFetchingItem: true }],
        [types.default.ADD_ACCOUNT, accountData],
        [types.default.SET_ACCOUNT_UI_FLAG, { isFetchingItem: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isFetchingItem: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isFetchingItem: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('sends correct actions if API is success', async () => {
      axios.patch.mockResolvedValue({
        data: { id: 1, name: 'John' },
      });
      await actions.update({ commit, getters }, accountData);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: true }],
        [types.default.EDIT_ACCOUNT, { id: 1, name: 'John' }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.update({ commit, getters }, accountData)
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#create', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({
        data: { data: { id: 1, name: 'John' } },
      });
      await actions.create({ commit, getters }, newAccountInfo);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isCreating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.create({ commit, getters }, newAccountInfo)
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isCreating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#toggleDeletion', () => {
    it('sends correct actions with delete action if API is success', async () => {
      axios.post.mockResolvedValue({});
      await actions.toggleDeletion({ commit }, { action_type: 'delete' });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: false }],
      ]);
      expect(axios.post.mock.calls[0][1]).toEqual({
        action_type: 'delete',
      });
    });

    it('sends correct actions with undelete action if API is success', async () => {
      axios.post.mockResolvedValue({});
      await actions.toggleDeletion({ commit }, { action_type: 'undelete' });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: false }],
      ]);
      expect(axios.post.mock.calls[0][1]).toEqual({
        action_type: 'undelete',
      });
    });

    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.toggleDeletion({ commit }, { action_type: 'delete' })
      ).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: true }],
        [types.default.SET_ACCOUNT_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#limits', () => {
    // ChatSPX: `actions.limits` comeca com uma guarda nossa —
    // `if (!rootGetters['globalConfig/isOnChatwootCloud']) return null`, porque
    // /enterprise/.../limits e exclusivo do Chatwoot Cloud e devolve 404 self-hosted.
    // Sem declarar a nuvem, a action retorna ANTES de qualquer commit e os exemplos abaixo
    // deixam de medir o que anunciam.
    const naNuvem = {
      getCurrentAccountId: 1,
      'globalConfig/isOnChatwootCloud': true,
    };

    it('marks endpoint as unavailable when limits route returns 404', async () => {
      axios.get.mockRejectedValue({ response: { status: 404 } });

      await actions.limits({
        commit,
        state: { limitsEndpointUnavailableByAccount: {} },
        rootGetters: naNuvem,
      });

      expect(commit).toHaveBeenCalledWith(types.default.SET_ACCOUNT_UI_FLAG, {
        isFetchingLimits: true,
      });
      expect(commit).toHaveBeenCalledWith(
        types.default.SET_ACCOUNT_LIMITS_ENDPOINT_UNAVAILABLE,
        {
          accountId: 1,
          unavailable: true,
        }
      );
      expect(commit).toHaveBeenCalledWith(types.default.SET_ACCOUNT_UI_FLAG, {
        isFetchingLimits: false,
      });
    });

    it('skips request when endpoint was previously marked as unavailable', async () => {
      await actions.limits({
        commit,
        state: { limitsEndpointUnavailableByAccount: { 1: true } },
        rootGetters: naNuvem,
      });

      expect(axios.get).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });

    // Este exemplo existe porque o de cima passava pelo motivo ERRADO: sem `naNuvem`, a
    // guarda de nuvem retornava primeiro e a assercao negativa ficava verde mesmo que a
    // logica do flag `unavailable` estivesse quebrada. Agora um exemplo cobre cada guarda.
    it('skips request entirely when the install is not on Chatwoot Cloud', async () => {
      await actions.limits({
        commit,
        state: { limitsEndpointUnavailableByAccount: {} },
        rootGetters: {
          getCurrentAccountId: 1,
          'globalConfig/isOnChatwootCloud': false,
        },
      });

      expect(axios.get).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });
  });
});
