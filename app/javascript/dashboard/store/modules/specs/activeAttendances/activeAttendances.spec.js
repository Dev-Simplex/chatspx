import axios from 'axios';
import { actions, mutations } from '../../activeAttendances';
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
        [
          types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG,
          { isFetching: true, hasError: false },
        ],
        [types.default.SET_ACTIVE_ATTENDANCES, apiResponse.payload],
        [
          types.default.SET_ACTIVE_ATTENDANCES_META,
          { count: 2, currentPage: 1, perPage: 15 },
        ],
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: false }],
      ]);
    });

    // Sem isto a falha viraria lista vazia = "ninguém em atendimento", que é a
    // resposta OPOSTA à verdade numa aba feita p/ responder "alguém já atende?".
    it('flags the error and empties the list when the API fails', async () => {
      axios.get.mockRejectedValue({ message: 'boom' });
      await expect(actions.get({ commit }, { page: 1 })).rejects.toBeTruthy();

      expect(commit.mock.calls).toEqual([
        [
          types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG,
          { isFetching: true, hasError: false },
        ],
        [types.default.SET_ACTIVE_ATTENDANCES, []],
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { hasError: true }],
        [types.default.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('rethrows so the page can keep the URL on the page that still renders', async () => {
      axios.get.mockRejectedValue(new Error('boom'));

      await expect(actions.get({ commit }, { page: 2 })).rejects.toThrow(
        'boom'
      );
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
