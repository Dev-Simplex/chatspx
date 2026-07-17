import axios from 'axios';
import { actions, getters, mutations } from '../../activeAttendances';
import * as types from '../../../mutation-types';
import apiResponse from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('commits the payload and meta when the API succeeds', async () => {
      axios.get.mockResolvedValue({ data: apiResponse });
      await actions.get({ commit }, { page: 1 });

      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: true }],
        [types.default.SET_ACTIVE_ATTENDANCES, apiResponse.payload],
        [
          types.default.SET_ACTIVE_ATTENDANCES_META,
          { count: 2, currentPage: 1 },
        ],
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('clears the fetching flag when the API fails', async () => {
      axios.get.mockRejectedValue({ message: 'boom' });
      await expect(actions.get({ commit }, { page: 1 })).rejects.toBeTruthy();

      expect(commit.mock.calls).toEqual([
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: true }],
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: false }],
      ]);
    });
  });
});

describe('#mutations', () => {
  it('camelCases the records deeply', () => {
    const state = { records: [] };
    mutations[types.default.SET_ACTIVE_ATTENDANCES](state, apiResponse.payload);

    expect(state.records[0].lastActivityAt).toBe(1750000500);
    expect(state.records[0].contact.phoneNumber).toBe('+5511999999999');
    expect(state.records[0].inbox.channelType).toBe('Channel::Api');
    expect(state.records[0].assignee.availableName).toBe('Ana');
  });
});

describe('#getters', () => {
  // A Fase 2 (aviso ao criar conversa) depende deste getter.
  it('getByContactId returns every attendance of a contact', () => {
    const state = {
      records: [
        { id: 11, contact: { id: 1 } },
        { id: 12, contact: { id: 5 } },
        // mesmo contato, outra caixa: é justamente a duplicação que a aba expõe
        { id: 13, contact: { id: 1 } },
      ],
    };

    expect(
      getters
        .getByContactId(state)(1)
        .map(r => r.id)
    ).toEqual([11, 13]);
    expect(
      getters
        .getByContactId(state)('1')
        .map(r => r.id)
    ).toEqual([11, 13]);
    expect(getters.getByContactId(state)(99)).toEqual([]);
  });
});
